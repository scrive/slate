module DumpEvidenceTexts (dumpAllEvidenceTexts) where

import Control.Applicative ((<$>))
import Control.Monad (forM, forM_, when)
import Control.Monad.Catch
import Control.Monad.Reader (asks)
import Control.Monad.Trans (liftIO)
import Data.Decimal (realFracToDecimal)
import Data.Function (on)
import Data.List (sortBy)
import Data.Maybe (fromJust, isNothing)
import System.FilePath ((</>))
import Test.Framework (Test)
import Text.StringTemplates.Templates (TemplatesMonad, renderTemplate)
import qualified Data.Set as Set
import qualified Text.StringTemplates.Fields as F

import DB (MonadDB)
import Doc.DocStateData (Document(..), SignatoryField(..), SignatoryLink(..), FieldType(..), DeliveryMethod(..), documentlang)
import Doc.DocumentMonad (withDocumentID, withDocument, theDocument)
import Doc.SignatoryFieldID
import Doc.SignatoryIdentification (signatoryIdentifierMap)
import Doc.SignatoryLinkID (unsafeSignatoryLinkID)
import EvidenceLog.Model (EventRenderTarget(..), DocumentEvidenceEvent(..), EvidenceEventType(..), CurrentEvidenceEventType(..), evidenceLogText)
import EvidenceLog.View (simpleEvents, simplyfiedEventText, eventForVerificationPage, finalizeEvidenceText)
import MinutesTime
import Templates (runTemplatesT)
import TestingUtil (testThat, addNewRandomUser, addRandomDocumentWithAuthor)
import TestKontra (TestEnvSt, teOutputDirectory, teGlobalTemplates)
import Text.XML.DirtyContent (renderXMLContent)
import User.Model (codeFromLang, Lang, allLangs)
import Util.Actor (Actor(..), actorEmail, actorUserID, actorAPIString, actorIP)
import Util.SignatoryLinkUtils (getAuthorSigLink)
import Utils.Default (defaultValue)
import Utils.Prelude (for)
import Version (versionID)

dumpAllEvidenceTexts :: TestEnvSt -> Test
dumpAllEvidenceTexts env = testThat "Generating all evidence texts" env $ do
  author <- addNewRandomUser
  did <- addRandomDocumentWithAuthor author
  withDocumentID did $ forM_ allLangs $ \lang -> do
    gts <- asks teGlobalTemplates
    now <- currentTime
    t <- runTemplatesT (lang, gts) $ theDocument >>= dumpEvidenceTexts now lang
    case teOutputDirectory env of
      Just d  -> liftIO $ writeFile (d </> "evidence-texts-" ++ codeFromLang lang ++ ".html") t
      Nothing -> t == t `seq` return ()

dumpEvidenceTexts :: (MonadDB m, MonadThrow m, TemplatesMonad m) => UTCTime -> Lang -> Document -> m String
dumpEvidenceTexts now lang doc' = do
  let Just author_sl' = getAuthorSigLink doc'
      author_sl = author_sl'
            { signatoryfields =
                  [ SignatoryField (unsafeSignatoryFieldID 0) FirstNameFT "Adam" True False []
                  , SignatoryField (unsafeSignatoryFieldID 0) LastNameFT "Author" True False []
                  , SignatoryField (unsafeSignatoryFieldID 0) EmailFT "author@example.com" True False []
                  ]
            , signatoryispartner = True
            , signatorylinkid = unsafeSignatoryLinkID 1
            }
  let Just time = parseTime' "%d-%m-%Y" "01-01-2013"
  let actor = Actor { actorTime = time
                    , actorClientTime = Nothing
                    , actorClientName = Nothing
                    , actorIP = Nothing
                    , actorUserID = Nothing
                    , actorEmail = Just "author@example.com"
                    , actorSigLinkID = Just (signatorylinkid author_sl)
                    , actorAPIString = Nothing
                    , actorWho = "the author (" ++ fromJust (actorEmail actor) ++ ")"
                    }
  let evidencetypes = [minBound .. maxBound]
  let asl = defaultValue
            { signatoryfields =
                  [ SignatoryField (unsafeSignatoryFieldID 0) FirstNameFT "Sven" True False []
                  , SignatoryField (unsafeSignatoryFieldID 0) LastNameFT "Signatory" True False []
                  , SignatoryField (unsafeSignatoryFieldID 0) EmailFT "signatory@example.com" True False []
                  ]
            , signatoryispartner = True
            , signatorylinkdeliverymethod = EmailAndMobileDelivery
            , signatorylinkid = unsafeSignatoryLinkID 2
            }
  let doc = doc' { documentsignatorylinks = [author_sl, asl] }
  let messageText = Just "This is a <b>message text.</b>"
  let fields t = do
        when (t `elem` [AutomaticReminderSent, ReminderSend, DeleteSigAttachmentEvidence, SaveSigAttachmentEvidence]) $ do
          F.value "author" $ actorEmail actor
        F.value "description" ("This is a description." :: String)
        F.value "lang" $ show lang
        F.value "msg" ("Really long message from external eID system." :: String)
        F.value "name" ("some name" :: String)
        F.value "newemail" ("good@example.com" :: String)
        F.value "newphone" ("good-12 34 56" :: String)
        F.value "oldemail" ("bad@example.com" :: String)
        F.value "oldphone" ("bad-12 34 56" :: String)
        F.value "timeouttime" $ formatTimeUTC time
        F.value "timezone" ("Europe/Stockholm" :: String)
        F.value "value" ("field value" :: String)
        F.value "fieldname" ("field name" :: String)
        F.objects "placements" $ for [(1::Int,0.123::Double,0.42::Double)] $ \(page,x,y) -> do
                       F.value "page" $ page
                       F.value "x" $ show $ realFracToDecimal 3 $ x
                       F.value "y" $ show $ realFracToDecimal 3 $ y
  let mkev text msgtext evt =
          DocumentEvidenceEvent { evDocumentID = documentid doc
                                , evTime = time
                                , evClientTime = Nothing
                                , evClientName = Nothing
                                , evClockErrorEstimate = Nothing
                                , evText = text
                                , evType = Current evt
                                , evVersionID = versionID
                                , evEmail = actorEmail actor
                                , evUserID = actorUserID actor
                                , evIP4 = actorIP actor
                                , evSigLink = actorSigLinkID actor
                                , evAPI = actorAPIString actor
                                , evAffectedSigLink = Just (signatorylinkid asl)
                                , evActor = actorWho actor
                                , evMessageText = msgtext
                                }
  evs <- (sortBy (compare `on` (\(evt, _, _, _) -> show evt)) <$>) $
         forM (evidencetypes) $ \evt -> do
       let text = case evt of
                    _ | evt `elem` [SMSPinSendEvidence, SMSPinDeliveredEvidence] -> Just "+481234567890"
                      | otherwise -> messageText
       elog <- withDocument doc $ evidenceLogText evt (fields evt) (Just asl) text
       let ev = mkev elog text evt
           sim = signatoryIdentifierMap True  [doc] (Set.fromList  [signatorylinkid asl])
       let simpletext target mactor = if simpleEvents (Current evt) && (isNothing mactor || eventForVerificationPage ev)
                                      then Just <$> simplyfiedEventText target mactor doc{ documentlang = lang } sim ev
                                      else return Nothing
       vp <- simpletext EventForVerificationPages (actorEmail actor)
       av <- simpletext EventForArchive Nothing
       return (evt, vp, av, finalizeEvidenceText sim ev)
  renderTemplate "dumpAllEvidenceTexts" $ do
     F.value "lang" $ codeFromLang lang
     F.value "versionID" versionID
     F.value "timestamp" $ show now
     F.objects "evidences" $ for evs $ \(evt, vp, av, elog) -> do
       F.value "name" $ show evt
       F.value "evidencelog" $ renderXMLContent elog
       F.value "authorview" $ av
       F.value "verificationpage" $ vp
