{-

* How it works *

When cron starts, it:

0. Checks database, parses configuration etc.

1. Inserts now() into cron_workers table and gets its unique id.

2. Spawns a thread (activity monitor), that will every minute update
last_activity column of the row with its id, then check for the workers
registered in cron_workers table whose last activity was more than 2
minutes ago. If it finds such records, the corresponding workers are
presumed to be dead and all tasks in cron_tasks that are supposedly
running with these workers are reset, i.e. worker_id is set to NULL.

3. Spawns a thread (task dispatcher), that will once per 5 seconds try
to select from cron_tasks table one task that should be run. If such
task is present, it reserves it by setting 'worker_id' to its id,
'started' to now() and then spawns a new thread that will execute the
task and either update its 'finished' column if the task was successful.
In either case worker_id is reset to NULL.

4. If termination signal is received, it waits for all currently running
tasks to finish, then deletes its corresponding row from cron_workers
table and exits.

* Additional assumptions *

1. Cron instances use SERIALIZABLE isolation level for
activity monitoring and task reservation to ensure validity.
2. If a cron instance exits without the chance to clean up (e.g. by
receiving SIGKILL), other instances will clean up its mess (release
tasks it possibly reserved and didn't finish) after at most 2 minutes.

* Guarantees *

1. A task will be executed at least once until it succeeds.
2. A task will never be started more than once in parallel.

-}
module Cron where

import Control.Concurrent
import Control.Monad
import Control.Monad.Trans
import qualified CronEnv
import qualified System.Time
import Data.Maybe
import Data.Monoid ((<>))
import Data.Monoid.Space
import qualified Control.Concurrent.Thread.Group as TG
import qualified Control.Exception as E

import ActionQueue.EmailChangeRequest
import ActionQueue.Monad
import ActionQueue.PasswordReminder
import ActionQueue.UserAccountRequest
import AppConf
import Configuration
import Cron.Model
import Crypto.RNG
import qualified Data.ByteString as BS
import DB
import DB.Checks
import DB.PostgreSQL
import Doc.API.Callback.Model
import Doc.AutomaticReminder.Model
import Doc.Action
import AppDBTables
import qualified MemCache
import Utils.IO
import Mails.Events
import SMS.Events
import MinutesTime
import Payments.Config
import Payments.Control
import HostClock.Collector (collectClockError)
import Session.Data
import Purging.Files
import Templates
import Doc.Model
import qualified Amazon as AWS
import qualified Log

import ThirdPartyStats.Core
import ThirdPartyStats.Mixpanel

main :: IO ()
main = Log.withLogger $ do
  appConf <- do
    readConfig Log.mixlog_ "kontrakcja.conf"

  checkExecutables

  connPool <- createPoolSource . pgConnSettings $ dbConfig appConf
  withPostgreSQL connPool $
    checkDatabase Log.mixlog_ kontraTables

  templates <- newMVar =<< liftM2 (,) getTemplatesModTime readGlobalTemplates
  rng <- newCryptoRNGState
  filecache <- MemCache.new BS.length 52428800

  let runScheduler = inDB . CronEnv.runScheduler appConf filecache templates
      inDB = liftIO . withPostgreSQL connPool . runCryptoRNGT rng
  -- Asynchronous event dispatcher; if you want to add a consumer to the event
  -- dispatcher, please combine the two into one dispatcher function rather
  -- than creating a new thread or something like that, since
  -- asyncProcessEvents removes events after processing.
  mmixpanel <- case mixpanelToken appConf of
    ""    -> Log.mixlog_ "WARNING: no Mixpanel token present!" >> return Nothing
    token -> return $ Just $ processMixpanelEvent token

  let dispatcher :: TaskType -> IO ()
      dispatcher tt = case tt of
        AmazonDeletion -> if AWS.isAWSConfigOk $ amazonConfig appConf
           then runScheduler purgeSomeFiles
           else Log.mixlog_ "AmazonDeletion: no valid AWS config, skipping."
        AmazonUpload -> if AWS.isAWSConfigOk $ amazonConfig appConf
          then runScheduler AWS.uploadFilesToAmazon
          else Log.mixlog_ "AmazonUpload: no valid AWS config, skipping."
        AsyncEventsProcessing -> inDB $ do
          asyncProcessEvents (catEventProcs $ catMaybes [mmixpanel]) All
        ClockErrorCollection -> withPostgreSQL connPool $
          collectClockError (ntpServers appConf)
        DocumentAPICallbackEvaluation -> runScheduler $
          actionQueue documentAPICallback
        DocumentAutomaticRemindersEvaluation -> runScheduler $
          actionQueue documentAutomaticReminder
        DocumentsPurge -> runScheduler $ do
          purgedCount <- dbUpdate $ PurgeDocuments 30 unsavedDocumentLingerDays
          Log.mixlog_ $ "DocumentsPurge: purged" <+> show purgedCount <+> "documents."
        EmailChangeRequestsEvaluation -> runScheduler $
          actionQueue emailChangeRequest
        FindAndDoPostDocumentClosedActions -> runScheduler $
          findAndDoPostDocumentClosedActions Nothing
        FindAndDoPostDocumentClosedActionsNew -> runScheduler $
          findAndDoPostDocumentClosedActions (Just 6) -- hours
        FindAndExtendDigitalSignatures -> runScheduler findAndExtendDigitalSignatures
        FindAndTimeoutDocuments -> runScheduler findAndTimeoutDocuments
        MailEventsProcessing -> runScheduler Mails.Events.processEvents
        OldDraftsRemoval -> runScheduler $ do
          delCount <- dbUpdate $ RemoveOldDrafts 100
          Log.mixlog_ $ "OldDraftsRemoval: removed" <+> show delCount <+> "old, unsaved draft documents."
        PasswordRemindersEvaluation -> runScheduler $ actionQueue passwordReminder
        RecurlySynchronization -> inDB $ do
          mtime <- getMinutesTime
          ctime <- liftIO $ System.Time.toCalendarTime (toClockTime mtime)
          temps <- snd `liftM` liftIO (readMVar templates)
          when (System.Time.ctHour ctime == 0) $ do -- midnight
            handleSyncWithRecurly appConf (mailsConfig appConf)
              temps (recurlyAPIKey $ recurlyConfig appConf) mtime
            handleSyncNoProvider mtime
        SessionsEvaluation -> runScheduler $ actionQueue session
        SMSEventsProcessing -> runScheduler SMS.Events.processEvents
        UserAccountRequestEvaluation -> runScheduler $ actionQueue userAccountRequest

      serializable = defaultTransactionSettings {
        tsIsolationLevel = Serializable
      , tsRestartPredicate = RestartPredicate $ const . ((SerializationFailure ==) . qeErrorCode)
      }

  tg <- TG.new
  mtid <- myThreadId
  wid <- withPostgreSQL connPool . dbUpdate $ RegisterWorker

  let cleanup = do
        Log.mixlog_ "Waiting for jobs to finish..."
        TG.wait tg
        withPostgreSQL connPool . dbUpdate $ UnregisterWorker wid

      -- helper threads are essential, therefore if one
      -- of them fails, let's kill the main thread.
      forkForever = void . forkIO . flip E.onException (killThread mtid) . forever

  flip E.finally cleanup $ do
    -- spawn task dispatcher
    forkForever $ do
      mtt <- runDBT connPool serializable . dbUpdate $ ReserveTask wid
      case mtt of
        Nothing -> threadDelay 5000000 -- pause for 5 seconds if there are no tasks
        Just tt -> void . TG.forkIO tg $ do
          Log.mixlog_ $ "Starting" <+> show tt <> "..."
          eres <- E.try $ dispatcher tt
          case eres of
            Right () -> do
              Log.mixlog_ $ show tt <+> "finished successfully."
              runDBT connPool serializable . dbUpdate $ UpdateTaskFinishedTime tt
            Left (ex::E.SomeException) -> do
              Log.attention_ $ show tt <+> "failed with" <+> show ex <> "."
              -- wait a second so that the task won't be immediately picked up
              threadDelay 1000000
              runDBT connPool serializable . dbUpdate $ ReleaseTask tt

    -- spawn activity monitor
    forkForever $ do
      threadDelay $ 60 * 1000000 -- wait 60 seconds
      n <- runDBT connPool serializable $ do
        dbUpdate $ UpdateWorkerActivity wid
        dbUpdate $ UnregisterWorkersInactiveFor (iminutes 2)
      when (n > 0) $
        Log.mixlog_ $ "Unregistered" <+> show n <+> "inactive workers."

    waitForTermination
