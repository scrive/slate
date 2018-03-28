module Doc.Sealing.Consumer (
    DocumentSealing
  , documentSealing
  ) where

import Control.Monad.Catch
import Control.Monad.IO.Class
import Control.Monad.Trans.Control
import Crypto.RNG
import Data.Aeson
import Data.ByteString (ByteString)
import Data.Int
import Database.PostgreSQL.Consumers.Config
import Log.Class
import qualified Database.Redis as R

import BrandedDomain.Model
import DB
import DB.PostgreSQL
import Doc.Action
import Doc.DocumentID
import Doc.DocumentMonad
import Doc.Sealing.Model
import File.FileID
import FileStorage
import GuardTime
import Log.Identifier
import MailContext
import MailContext.Internal
import MemCache (MemCache)
import PdfToolsLambda.Conf
import Templates
import User.Lang
import qualified FileStorage.Amazon.Config as A

data DocumentSealing = DocumentSealing {
    dsDocumentID      :: !DocumentID
  , dsBrandedDomainID :: !BrandedDomainID
  , dsAttempts        :: !Int32
  }

documentSealing
  :: (CryptoRNG m, MonadLog m, MonadIO m, MonadBaseControl IO m, MonadMask m)
  => Maybe A.AmazonConfig
  -> GuardTimeConf
  -> PdfToolsLambdaConf
  -> KontrakcjaGlobalTemplates
  -> MemCache FileID ByteString
  -> Maybe R.Connection
  -> ConnectionSourceM m
  -> String
  -> Int
  -> ConsumerConfig m DocumentID DocumentSealing
documentSealing mAmazonConfig guardTimeConf pdfToolsLambdaConf templates _ mRedisConn pool
                mailNoreplyAddress maxRunningJobs = ConsumerConfig {
    ccJobsTable = "document_sealing_jobs"
  , ccConsumersTable = "document_sealing_consumers"
  , ccJobSelectors = ["id", "branded_domain_id", "attempts"]
  , ccJobFetcher = \(did, bdid, attempts) -> DocumentSealing {
      dsDocumentID      = did
    , dsBrandedDomainID = bdid
    , dsAttempts        = attempts
    }
  , ccJobIndex = dsDocumentID
  , ccNotificationChannel = Just documentSealingNotificationChannel
  , ccNotificationTimeout = 60 * 1000000 -- 1 minute
  , ccMaxRunningJobs = maxRunningJobs
  , ccProcessJob = \docsealing@DocumentSealing{..} -> withPostgreSQL pool . withDocumentID dsDocumentID $ do
      now0 <- currentTime
      bd <- dbQuery $ GetBrandedDomainByID dsBrandedDomainID
      doc <- theDocument
      let lang = getLang doc
          mc = MailContext {
              _mctxlang                 = lang
            , _mctxcurrentBrandedDomain = bd
            , _mctxtime                 = now0
            , _mctxmailNoreplyAddress   = mailNoreplyAddress
            }
      resultisok <- runGuardTimeConfT guardTimeConf
        . runPdfToolsLambdaConfT pdfToolsLambdaConf
        . runTemplatesT (lang, templates)
        . runMailContextT mc
        . runFileStorageT (mAmazonConfig, mRedisConn)
        $ postDocumentClosedActions True False
      case resultisok of
        True  -> return $ Ok Remove
        False -> Failed <$> onFailure docsealing
  , ccOnException = const onFailure
  }
  where
    onFailure DocumentSealing{..} = do
      when (dsAttempts > 1) $ do
        logAttention "Document sealing failed more than 1 time" $ object [
            identifier_ dsDocumentID
          , "attempt_count" .= dsAttempts
          ]
      return . RerunAfter . attemptToDelay $ dsAttempts

    attemptToDelay 1 = iminutes 5
    attemptToDelay 2 = iminutes 10
    attemptToDelay 3 = iminutes 30
    attemptToDelay 4 = ihours 1
    attemptToDelay 5 = ihours 2
    attemptToDelay 6 = ihours 4
    attemptToDelay 7 = ihours 8
    attemptToDelay 8 = ihours 16
    attemptToDelay _ = idays 1
