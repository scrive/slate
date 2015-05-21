module JobQueue.Components (
    runConsumer
  , spawnListener
  , spawnMonitor
  , spawnDispatcher
  ) where

import Control.Applicative
import Control.Concurrent.Lifted
import Control.Concurrent.STM hiding (atomically)
import Control.Exception (AsyncException(ThreadKilled))
import Control.Monad
import Control.Monad.Base
import Control.Monad.Catch
import Control.Monad.Trans
import Control.Monad.Trans.Control
import Data.Int
import Data.Function
import Data.Monoid
import Data.Monoid.Utils
import Database.PostgreSQL.PQTypes
import Log
import Prelude
import qualified Control.Concurrent.STM as STM
import qualified Control.Concurrent.Thread.Lifted as T
import qualified Data.Foldable as F
import qualified Data.Map.Strict as M

import JobQueue.Config
import JobQueue.Consumer
import JobQueue.Utils

-- | Run the consumer. The purpose of the returned monadic
-- action is to wait for currently processed jobs and clean up.
runConsumer
  :: (MonadBaseControl IO m, MonadLog m, MonadMask m, Eq idx, Show idx, ToSQL idx)
  => ConsumerConfig m idx job
  -> ConnectionSource
  -> m (m ())
runConsumer cc cs = do
  semaphore <- newMVar ()
  runningJobsInfo <- liftBase $ newTVarIO M.empty
  runningJobs <- liftBase $ newTVarIO 0

  cid <- registerConsumer cc cs
  localData ["consumer_id" .= show cid] $ do
    listener <- spawnListener cc cs semaphore
    monitor <- localDomain "monitor" $ spawnMonitor cc cs cid
    dispatcher <- localDomain "dispatcher" $ spawnDispatcher cc cs cid semaphore runningJobsInfo runningJobs
    return . localDomain "finalizer" $ do
      stopExecution listener
      stopExecution dispatcher
      waitForRunningJobs runningJobsInfo runningJobs
      stopExecution monitor
      unregisterConsumer cc cs cid
  where
    waitForRunningJobs runningJobsInfo runningJobs = do
      initialJobs <- liftBase $ readTVarIO runningJobsInfo
      (`fix` initialJobs) $ \loop jobsInfo -> do
        -- If jobs are still running, display info about them.
        when (not $ M.null jobsInfo) $ do
          logInfo "Waiting for running jobs" $ object [
              "job_id" .= showJobsInfo jobsInfo
            ]
        join . atomically $ do
          jobs <- readTVar runningJobs
          if jobs == 0
            then return $ return ()
            else do
              newJobsInfo <- readTVar runningJobsInfo
              -- If jobs info didn't change, wait for it to change.
              -- Otherwise loop so it either displays the new info
              -- or exits if there are no jobs running anymore.
              if (newJobsInfo == jobsInfo)
                then retry
                else return $ loop newJobsInfo
      where
        showJobsInfo = M.foldr (\idx acc -> show idx : acc) []

-- | Spawn a thread that generates signals for the
-- dispatcher to probe the database for incoming jobs.
spawnListener
  :: (MonadBaseControl IO m, MonadMask m)
  => ConsumerConfig m idx job
  -> ConnectionSource
  -> MVar ()
  -> m ThreadId
spawnListener cc cs semaphore = forkP "listener" $ case ccNotificationChannel cc of
  Just chan -> runDBT cs noTs . bracket_ (listen chan) (unlisten chan) . forever $ do
    -- If there are many notifications, we need to collect them
    -- as soon as possible, because they are stored in memory by
    -- libpq. They are also not squashed, so we perform the
    -- squashing ourselves with the help of MVar ().
    void . getNotification $ ccNotificationTimeout cc
    lift signalDispatcher
  Nothing -> forever $ do
    liftBase . threadDelay $ ccNotificationTimeout cc
    signalDispatcher
  where
    signalDispatcher = do
      liftBase $ tryPutMVar semaphore ()

    noTs = def {
      tsAutoTransaction = False
    }

-- | Spawn a thread that monitors working consumers
-- for activity and periodically updates its own.
spawnMonitor
  :: (MonadBaseControl IO m, MonadLog m, MonadMask m)
  => ConsumerConfig m idx job
  -> ConnectionSource
  -> ConsumerID
  -> m ThreadId
spawnMonitor ConsumerConfig{..} cs cid = forkP "monitor" . forever $ do
  runDBT cs ts $ do
    -- Update last_activity of the consumer.
    ok <- runSQL01 $ smconcat [
        "UPDATE" <+> raw ccConsumersTable
      , "SET last_activity = now()"
      , "WHERE id =" <?> cid
      , "  AND name =" <?> unRawSQL ccJobsTable
      ]
    if ok
      then logInfo_ "Activity of the consumer updated"
      else do
        logInfo_ $ "Consumer is not registered"
        throwM ThreadKilled
  -- Freeing jobs locked by inactive consumers needs to happen
  -- exactly once, otherwise it's possible to free it twice, after
  -- it was already marked as reserved by other consumer, so let's
  -- run it in serializable transaction.
  (inactiveConsumers, freedJobs) <- runDBT cs tsSerializable $ do
    -- Delete all inactive (assumed dead) consumers and get their ids.
    runSQL_ $ smconcat [
        "DELETE FROM" <+> raw ccConsumersTable
      , "  WHERE last_activity +" <?> iminutes 1 <+> "<= now()"
      , "    AND name =" <?> unRawSQL ccJobsTable
      , "  RETURNING id::bigint"
      ]
    inactive :: [Int64] <- fetchMany runIdentity
    -- Reset reserved jobs manually, do not rely
    -- on the foreign key constraint to do its job.
    freed <- if null inactive
      then return 0
      else runSQL $ smconcat [
        "UPDATE" <+> raw ccJobsTable
      , "SET reserved_by = NULL"
      , "WHERE reserved_by = ANY(" <?> Array1 inactive <+> ")"
      ]
    return (length inactive, freed)
  when (inactiveConsumers > 0) $ do
    logInfo "Unregistered inactive consumers" $ object [
        "inactive_consumers" .= inactiveConsumers
      ]
  when (freedJobs > 0) $ do
    logInfo "Freed locked jobs" $ object [
        "freed_jobs" .= freedJobs
      ]
  liftBase . threadDelay $ 30 * 1000000 -- wait 30 seconds
  where
    tsSerializable = ts {
      tsIsolationLevel = Serializable
    }

-- | Spawn a thread that reserves and processes jobs.
spawnDispatcher
  :: forall m idx job. (MonadBaseControl IO m, MonadLog m, MonadMask m, Show idx, ToSQL idx)
  => ConsumerConfig m idx job
  -> ConnectionSource
  -> ConsumerID
  -> MVar ()
  -> TVar (M.Map ThreadId idx)
  -> TVar Int
  -> m ThreadId
spawnDispatcher ConsumerConfig{..} cs cid semaphore runningJobsInfo runningJobs =
  forkP "dispatcher" . forever $ do
    void $ takeMVar semaphore
    loop 1
  where
    loop :: Int -> m ()
    loop limit = do
      (batch, batchSize) <- reserveJobs limit
      when (batchSize > 0) $ do
        logInfo "Processing batch" $ object [
            "batch_size" .= batchSize
          ]
        -- Update runningJobs before forking so that we can
        -- adjust maxBatchSize appropriately later. We also
        -- need to mask asynchronous exceptions here as we
        -- rely on correct value of runningJobs to perform
        -- graceful termination.
        mask $ \restore -> do
          atomically $ modifyTVar' runningJobs (+batchSize)
          let subtractJobs = atomically $ do
                modifyTVar' runningJobs (subtract batchSize)
          void . forkP "batch processor" . (`finally` subtractJobs) . restore $ do
            mapM startJob batch >>= mapM joinJob >>= updateJobs

        when (batchSize == limit) $ do
          maxBatchSize <- atomically $ do
            jobs <- readTVar runningJobs
            when (jobs >= ccMaxRunningJobs) retry
            return $ ccMaxRunningJobs - jobs
          loop $ min maxBatchSize (2*limit)

    reserveJobs :: Int -> m ([job], Int)
    reserveJobs limit = runDBT cs ts $ do
      n <- runSQL $ smconcat [
          "UPDATE" <+> raw ccJobsTable <+> "SET"
        , "  reserved_by =" <?> cid
        , ", attempts = CASE"
        , "    WHEN finished_at IS NULL THEN attempts + 1"
        , "    ELSE 1"
        , "  END"
        , "WHERE id IN (" <> reservedJobs <> ")"
        , "RETURNING" <+> mintercalate ", " ccJobSelectors
        ]
      -- Decode lazily as we want the transaction to be as short as possible.
      (, n) . F.toList . fmap ccJobFetcher <$> queryResult
      where
        reservedJobs :: SQL
        reservedJobs = smconcat [
            "SELECT id FROM" <+> raw ccJobsTable
            -- Converting id to text and hashing it may seem silly,
            -- especially when we're dealing with integers in the first
            -- place, but even in such case the overhead is small enough
            -- (converting 100k integers to text and hashing them takes
            -- around 15 ms on i7) to be worth the generality.
            -- Also: after PostgreSQL 9.5 is released, we can use SELECT
            -- FOR UPDATE SKIP LOCKED instead of advisory locks (see
            -- http://michael.otacoo.com/postgresql-2/postgres-9-5-feature-highlight-skip-locked-row-level/
            -- for more details). Also, note that even if IDs of two
            -- pending jobs produce the same hash, it just means that
            -- in the worst case they will be processed by the same consumer.
          , "WHERE pg_try_advisory_xact_lock(" <?> unRawSQL ccJobsTable <> "::regclass::integer, hashtext(id::text))"
          , "  AND reserved_by IS NULL"
          , "  AND run_at IS NOT NULL"
          , "  AND run_at <= now()"
          , "LIMIT" <?> limit
          , "FOR UPDATE"
          ]

    -- | Spawn each job in a separate thread.
    startJob :: job -> m (job, m (T.Result Result))
    startJob job = do
      (_, joinFork) <- mask $ \restore -> T.fork $ do
        tid <- myThreadId
        bracket_ (registerJob tid) (unregisterJob tid) . restore $ do
          ccProcessJob job
      return (job, joinFork)
      where
        registerJob tid = atomically $ do
          modifyTVar' runningJobsInfo . M.insert tid $ ccJobIndex job
        unregisterJob tid = atomically $ do
           modifyTVar' runningJobsInfo $ M.delete tid

    -- | Wait for all the jobs and collect their results.
    joinJob :: (job, m (T.Result Result)) -> m (idx, Result)
    joinJob (job, joinFork) = joinFork >>= \eres -> case eres of
      Right result -> return (ccJobIndex job, result)
      Left ex -> do
        action <- ccOnException ex job
        logAttention "Unexpected exception caught while processing job" $ object [
            "job_id" .= show (ccJobIndex job)
          , "exception" .= show ex
          , "action" .= show action
          ]
        return (ccJobIndex job, Failed action)

    -- | Update status of the jobs.
    updateJobs :: [(idx, Result)] -> m ()
    updateJobs results = runDBT cs ts $ do
      runSQL_ $ smconcat [
          "WITH removed AS ("
        , "  DELETE FROM" <+> raw ccJobsTable
        , "  WHERE id = ANY(" <?> Array1 deletes <+> ")"
        , ")"
        , "UPDATE" <+> raw ccJobsTable <+> "SET"
        , "  reserved_by = NULL"
        , ", run_at = CASE"
        , "    WHEN FALSE THEN run_at"
        ,      smconcat $ M.foldrWithKey retryToSQL [] retries
        , "    ELSE NULL" -- processed
        , "  END"
        , ", finished_at = CASE"
        , "    WHEN id = ANY(" <?> Array1 successes <+> ") THEN now()"
        , "    ELSE NULL"
        , "  END"
        , "WHERE id = ANY(" <?> Array1 (map fst updates) <+> ")"
        ]
      where
        retryToSQL (Left int) ids =
          ("WHEN id = ANY(" <?> Array1 ids <+> ") THEN now() +" <?> int :)
        retryToSQL (Right time) ids =
          ("WHEN id = ANY(" <?> Array1 ids <+> ") THEN" <?> time :)

        retries = foldr step M.empty $ map f updates
          where
            f (idx, result) = case result of
              Ok     action -> (idx, action)
              Failed action -> (idx, action)

            step (idx, action) iretries = case action of
              MarkProcessed  -> iretries
              RerunAfter int -> M.insertWith (++) (Left int) [idx] iretries
              RerunAt time   -> M.insertWith (++) (Right time) [idx] iretries
              Remove         -> error "updateJobs: Remove should've been filtered out"

        successes = foldr step [] updates
          where
            step (idx, Ok     _) acc = idx : acc
            step (_,   Failed _) acc =       acc

        (deletes, updates) = foldr step ([], []) results
          where
            step job@(idx, result) (ideletes, iupdates) = case result of
              Ok     Remove -> (idx : ideletes, iupdates)
              Failed Remove -> (idx : ideletes, iupdates)
              _             -> (ideletes, job : iupdates)

----------------------------------------

ts :: TransactionSettings
ts = def {
  tsIsolationLevel = ReadCommitted
, tsPermissions = ReadWrite
  -- PostgreSQL doesn't seem to handle very high amount of
  -- concurrent transactions that modify multiple rows in
  -- the same table well (see updateJobs) and sometimes (very
  -- rarely though) ends up in a deadlock. It doesn't matter
  -- much though, we just restart the transaction in such case.
, tsRestartPredicate = Just . RestartPredicate
  $ \e _ -> qeErrorCode e == DeadlockDetected
         || qeErrorCode e == SerializationFailure
}

atomically :: MonadBase IO m => STM a -> m a
atomically = liftBase . STM.atomically
