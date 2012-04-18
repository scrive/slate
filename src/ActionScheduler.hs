module ActionScheduler (
      ActionScheduler
    , runScheduler
    , actionScheduler
    , oldScheduler
    , runDocumentProblemsCheck
    , runArchiveProblemsCheck
    , getGlobalTemplates
    ) where

import Control.Applicative
import Control.Concurrent
import Control.Monad.Base
import Control.Monad.Reader
import Control.Monad.Trans.Control
import Data.List
import Happstack.State
import qualified Control.Exception.Lifted as E

import AppControl (AppConf(..))
import ActionSchedulerState
import Control.Monad.Trans.Control.Util
import Crypto.RNG
import DB hiding (update, query)
import DB.PostgreSQL
import Doc.DocStateData
import Doc.Model
import MinutesTime
import Mails.MailsData
import Mails.SendMail
import Session
import Templates.TemplatesLoader
import qualified Log
import System.Time
import Doc.Invariants
import Stats.Control
import EvidenceLog.Model

type SchedulerData' = SchedulerData AppConf (MVar (ClockTime, KontrakcjaGlobalTemplates))

type InnerAS = ReaderT SchedulerData' (CryptoRNGT (DBT IO))

newtype ActionScheduler a = AS { unAS :: InnerAS a }
  deriving (Applicative, CryptoRNG, Functor, Monad, MonadBase IO, MonadDB, MonadIO, MonadReader SchedulerData')

instance MonadBaseControl IO ActionScheduler where
  newtype StM ActionScheduler a = StAS { unStAS :: StM InnerAS a }
  liftBaseWith = newtypeLiftBaseWith AS unAS StAS
  restoreM = newtypeRestoreM AS unStAS
  {-# INLINE liftBaseWith #-}
  {-# INLINE restoreM #-}

-- Note: Do not define TemplatesMonad instance for ActionScheduler, use
-- LocalTemplates instead. Reason? We don't have access to currently used
-- language, so we should rely on user's language settings the action is
-- assigned to and since TemplatesMonad doesn't give us the way to get
-- appropriate language version of templates, we need to do that manually.

runScheduler :: CryptoRNGState -> ActionScheduler () -> SchedulerData' -> IO ()
runScheduler rng sched sd =
  withPostgreSQL (dbConfig $ sdAppConf sd) . runCryptoRNGT rng $
    runReaderT (unAS sched) sd

-- | Gets 'expired' actions and evaluates them
actionScheduler :: ActionImportance -> ActionScheduler ()
actionScheduler imp = getMinutesTime
  >>= query . GetExpiredActions imp
  >>= mapM_ (\a -> do
    res <- E.try $ evaluateAction a
    case res of
      Left (e::E.SomeException) -> do
        printError a e
        dbRollback
      Right () -> do
        printSuccess a
        dbCommit
    )
  where
    printSuccess a = Log.debug $ "Action " ++ show a ++ " evaluated successfully"
    printError a e = Log.error $ "Oops, evaluateAction with " ++ show a ++ " failed with error: " ++ show e

-- | Old scheduler (used as main one before action scheduler was implemented)
oldScheduler :: ActionScheduler ()
oldScheduler = do
  now <- getMinutesTime
  timeoutDocuments now
  dropExpiredSessions now

-- Internal stuff

-- | Evaluates one action depending on its type
evaluateAction :: Action -> ActionScheduler ()
evaluateAction Action{actionID, actionType = PasswordReminder{}} =
    deleteAction actionID

evaluateAction Action{actionID, actionType = ViralInvitationSent{}} =
    deleteAction actionID

evaluateAction Action{actionID, actionType = AccountCreated{}} =
    deleteAction actionID

evaluateAction Action{actionID, actionType = AccountCreatedBySigning{}} = do
  -- we used to send a "You haven't secured your original" email,
  -- but we don't anymore, so this just deletes the action
  deleteAction actionID

evaluateAction Action{actionID, actionType = RequestEmailChange{}} =
  deleteAction actionID

evaluateAction Action{actionID, actionType = DummyActionType} =
  deleteAction actionID

runDocumentProblemsCheck :: ActionScheduler ()
runDocumentProblemsCheck = do
  sd <- ask
  now <- liftIO getMinutesTime
  docs <- dbQuery $ GetDocumentsByService Nothing
  let probs = listInvariantProblems now docs
  when (probs /= []) $ mailDocumentProblemsCheck $
    "<p>"  ++ (hostpart $ sdAppConf sd) ++ "/dave/document/" ++
    intercalate ("</p>\n\n<p>" ++ (hostpart $ sdAppConf sd) ++ "/dave/document/") probs ++
    "</p>"
  return ()

-- | Send an email out to all registered emails about document problems.
mailDocumentProblemsCheck :: String -> ActionScheduler ()
mailDocumentProblemsCheck msg = do
  sd <- ask
  scheduleEmailSendout (mailsConfig $ sdAppConf sd) $ Mail {
      to = zipWith MailAddress documentProblemsCheckEmails documentProblemsCheckEmails
    , title = "Document problems report " ++ (hostpart $ sdAppConf sd)
    , content = msg
    , attachments = []
    , from = Nothing
    , mailInfo = None
    }

-- | A message will be sent to these email addresses when there is an inconsistent document found in the database.
documentProblemsCheckEmails :: [String]
documentProblemsCheckEmails = ["bugs@skrivapa.se"]

runArchiveProblemsCheck :: ActionScheduler ()
runArchiveProblemsCheck = do
  return ()

{-

  This requires reorganization as there is no difference between personal and company documents now.

  users <- dbQuery $ GetUsers
  personaldocs <- mapM getPersonalDocs users
  superviseddocs <- mapM getSupervisedDocs users
  let personaldocprobs = listPersonalDocInvariantProblems personaldocs
      supervisedocprobs = listSupervisedDocInvariantProblems superviseddocs
      probs = unlines personaldocprobs ++ unlines supervisedocprobs
  when (probs /= []) $ mailArchiveProblemsCheck probs
  return ()
  where
    getPersonalDocs user = do
      docs <- dbQuery $ GetDocumentsBySignatory [Contract, Offer, Order] user
      return (user, docs)
    getSupervisedDocs user = do
      docs <- dbQuery $ GetDocumentsByCompany user
      return (user, docs)

mailArchiveProblemsCheck :: String -> ActionScheduler ()
mailArchiveProblemsCheck msg = do
  sd <- ask
  scheduleEmailSendout (sdMailsConfig sd) $ Mail { to = zipWith MailAddress archiveProblemsCheckEmails archiveProblemsCheckEmails
                                                  , title = "Archive problems report " ++ (hostpart $ sdAppConf sd)
                                                  , content = msg
                                                  , attachments = []
                                                  , from = Nothing
                                                  , mailInfo = None
                                                  }
archiveProblemsCheckEmails :: [BS.ByteString]
archiveProblemsCheckEmails = map BS.fromString ["emily@scrive.com"]

-}

deleteAction :: ActionID -> ActionScheduler ()
deleteAction aid = do
    _ <- update $ DeleteAction aid
    return ()

getGlobalTemplates :: ActionScheduler KontrakcjaGlobalTemplates
getGlobalTemplates = do
    sd <- ask
    (_, templates) <- liftIO $ readMVar (sdTemplates sd)
    return templates

-- Old scheduler internal stuff

timeoutDocuments :: MinutesTime -> ActionScheduler ()
timeoutDocuments now = do
    docs <- dbQuery $ GetTimeoutedButPendingDocuments now
    forM_ docs $ \doc -> do
        edoc <- dbUpdate $ TimeoutDocument (documentid doc) (systemActor now)
        case edoc of
          Left _ -> return ()
          Right doc' -> do
            _ <- addDocumentTimeoutStatEvents doc'
            return ()
        Log.debug $ "Document timedout " ++ (show $ documenttitle doc)

