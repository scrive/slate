module CronMain where

import Control.Concurrent
import Control.Monad
import Control.Monad.Trans
import qualified CronEnv
import System.Environment
import qualified System.Time
import Data.Maybe (catMaybes)

import ActionQueue.EmailChangeRequest
import ActionQueue.Monad
import ActionQueue.PasswordReminder
import ActionQueue.UserAccountRequest
import AppConf
import Configuration
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
import Utils.Cron
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
    appname <- getProgName
    args <- getArgs
    readConfig Log.mixlog_ appname args "kontrakcja.conf"

  checkExecutables

  let connSource = defaultSource . pgConnSettings $ dbConfig appConf
  withPostgreSQL connSource $
    checkDatabase Log.mixlog_ kontraTables

  templates <- newMVar =<< liftM2 (,) getTemplatesModTime readGlobalTemplates
  rng <- newCryptoRNGState
  filecache <- MemCache.new BS.length 52428800

  let runScheduler = inDB . CronEnv.runScheduler appConf filecache templates
      inDB = liftIO . withPostgreSQL connSource . runCryptoRNGT rng
  -- Asynchronous event dispatcher; if you want to add a consumer to the event
  -- dispatcher, please combine the two into one dispatcher function rather
  -- than creating a new thread or something like that, since
  -- asyncProcessEvents removes events after processing.
  mmixpanel <- case mixpanelToken appConf of
    ""    -> Log.mixlog_ "WARNING: no Mixpanel token present!" >> return Nothing
    token -> return $ Just $ processMixpanelEvent token

  withCronJobs
    ([ forkCron_ True "findAndExtendDigitalSignatures" (60 * 60 * 3) $ do
         Log.mixlog_ "Running findAndExtendDigitalSignatures..."
         runScheduler findAndExtendDigitalSignatures
     , forkCron_ True "findAndDoPostDocumentClosedActions (new)" (60 * 10) $ do
         Log.mixlog_ "Running findAndDoPostDocumentClosedActions (new)..."
         runScheduler $ findAndDoPostDocumentClosedActions (Just 6) -- hours
     , forkCron_ True "findAndDoPostDocumentClosedActions" (60 * 60 * 6) $ do
         Log.mixlog_ "Running findAndDoPostDocumentClosedActions..."
         runScheduler $ findAndDoPostDocumentClosedActions Nothing
     , forkCron_ True "findAndTimeoutDocuments" (60 * 10) $ do
         Log.mixlog_ "Running findAndTimeoutDocuments..."
         runScheduler findAndTimeoutDocuments
     , forkCron_ False "PurgeDocuments" (60 * 10) $ do
         Log.mixlog_ "Running PurgeDocuments..."
         runScheduler $ do
           purgedCount <- dbUpdate $ PurgeDocuments 30 unsavedDocumentLingerDays
           Log.mixlog_ $ "Purged " ++ show purgedCount ++ " documents."
     , forkCron_ True "EmailChangeRequests" (60 * 60) $ do
         Log.mixlog_ "Evaluating EmailChangeRequest actions..."
         runScheduler $ actionQueue emailChangeRequest
     , forkCron_ True "PasswordReminders" (60 * 60) $ do
         Log.mixlog_ "Evaluating PasswordReminder actions..."
         runScheduler $ actionQueue passwordReminder
     , forkCron_ True "UserAccountRequests" (60 * 60) $ do
         Log.mixlog_ "Evaluating UserAccountRequest actions..."
         runScheduler $ actionQueue userAccountRequest
     , forkCron False "Clock error collector" (60 * 60) $
         \interruptible -> withPostgreSQL connSource $
           collectClockError (ntpServers appConf) interruptible
     , forkCron_ True "Sessions" (60 * 60) $ do
         Log.mixlog_ "Evaluating sessions..."
         runScheduler $ actionQueue session
     , forkCron_ True "EventsProcessing" 5 $ do
         runScheduler Mails.Events.processEvents
     , forkCron_ True "SMSEventsProcessing" 5 $ do
         runScheduler SMS.Events.processEvents
     , forkCron_ True "DocumentAPICallback" 10 $ do
         runScheduler $ actionQueue documentAPICallback
     , forkCron_ True "DocumentAutomaticReminders" 60 $ do
         runScheduler $ actionQueue documentAutomaticReminder
     , forkCron_ True "RecurlySync" (55 * 60) . inDB $ do
         mtime <- getMinutesTime
         ctime <- liftIO $ System.Time.toCalendarTime (toClockTime mtime)
         temps <- snd `liftM` liftIO (readMVar templates)
         when (System.Time.ctHour ctime == 0) $ do -- midnight
           handleSyncWithRecurly appConf (mailsConfig appConf)
             temps (recurlyAPIKey $ recurlyConfig appConf) mtime
           handleSyncNoProvider mtime
     ] ++ (if AWS.isAWSConfigOk $ amazonConfig appConf
           then [forkCron_ True "AmazonUploading" 60 $ runScheduler AWS.uploadFilesToAmazon]
           else []) ++
          (if AWS.isAWSConfigOk $ amazonConfig appConf
           then [forkCron_ True "AmazonDeleting" (3*60*60) $ runScheduler purgeSomeFiles]
           else []) ++
     [ forkCron_ True "removeOldDrafts" (60 * 60) $ do
         Log.mixlog_ "Removing old, unsaved draft documents..."
         runScheduler $ do
           delCount <- dbUpdate $ RemoveOldDrafts 100
           Log.mixlog_ $ "Removed " ++ show delCount ++ " old, unsaved draft documents."
     , forkCron_ True "Async Event Dispatcher" (10) . inDB $ do
         asyncProcessEvents (catEventProcs $ catMaybes [mmixpanel]) All
     ]) $ \_ -> do
       waitForTermination
       Log.mixlog_ $ "Termination request received, waiting for jobs to finish..."
