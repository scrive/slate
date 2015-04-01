module EvidenceLog.View (
      eventsJSListFromEvidenceLog
    , eventsForLog
    , getSignatoryIdentifierMap
    , simplyfiedEventText
    , approximateActor
    , htmlDocFromEvidenceLog
    , finalizeEvidenceText
    , suppressRepeatedEvents
    , htmlSkipedEvidenceType
    , evidenceOfIntentHTML
    , simpleEvents
    , eventForVerificationPage
  ) where

import Control.Monad.Catch
import Data.Decimal (realFracToDecimal)
import Data.Function (on)
import Data.String.Utils as String
import Data.Word (Word8)
import Text.JSON
import Text.JSON.Gen as J
import Text.StringTemplates.Templates
import qualified Data.Foldable as F
import qualified Data.Map as Map
import qualified Data.Set as Set
import qualified Data.Text as T
import qualified Text.StringTemplates.Fields as F

import Control.Logic
import DB
import Doc.DocStateData
import Doc.Model (GetDocumentsBySignatoryLinkIDs(..))
import Doc.SignatoryIdentification (SignatoryIdentifierMap, siLink, siFullName, signatoryIdentifierMap, signatoryIdentifier)
import EID.Signature.Model
import EvidenceLog.Model
import KontraPrelude
import MinutesTime
import Templates (renderLocalTemplate)
import Text.XML.Content (cdata)
import Text.XML.DirtyContent (XMLContent, renderXMLContent, substitute)
import User.Model
import Util.HasSomeUserInfo
import Util.SignatoryLinkUtils
import Utils.Image
import Utils.Prelude
import qualified Doc.Screenshot as Screenshot
import qualified Doc.SignatoryScreenshots as SignatoryScreenshots
import qualified HostClock.Model as HC

-- | Evidence log for web page - short and simplified texts
eventsJSListFromEvidenceLog ::  (MonadDB m, MonadThrow m, TemplatesMonad m) => Document -> [DocumentEvidenceEvent] -> m [JSValue]
eventsJSListFromEvidenceLog doc dees = do
  let evs = eventsForLog dees
  sim <- getSignatoryIdentifierMap True evs
  mapM (J.runJSONGenT . eventJSValue doc sim) evs

-- | Get signatory identifier map from event list
getSignatoryIdentifierMap :: (MonadDB m, MonadThrow m) => Bool -> [DocumentEvidenceEvent] -> m SignatoryIdentifierMap
getSignatoryIdentifierMap includeviewers evs = do
  let sigs = Set.fromList $ catMaybes $ concat [ [evSigLink ev, evAffectedSigLink ev] | ev <- evs ]
  docs <- dbQuery $ GetDocumentsBySignatoryLinkIDs $ Set.toList sigs
  return $ signatoryIdentifierMap includeviewers (sortBy (compare `on` documentid) docs) sigs

-- | Keep only simple events, remove some redundant signatory events after signing
eventsForLog :: [DocumentEvidenceEvent] -> [DocumentEvidenceEvent]
eventsForLog = cleanUnimportantAfterSigning . filter ((simpleEvents . evType) &&^ (not . emptyEvent))

-- TODO: Consider saving actor name in event instead, this is likely to become broken
approximateActor :: (MonadDB m, MonadThrow m, TemplatesMonad m) => EventRenderTarget -> Document -> SignatoryIdentifierMap -> DocumentEvidenceEvent -> m String
approximateActor EventForEvidenceLog _ _ _ = $unexpectedErrorM "approximateActor should not be called for evidence log entries"
approximateActor tgt doc sim dee | systemEvents $ evType dee = return "Scrive"
                             | otherwise = do
  emptyNamePlaceholder <- renderTemplate_ "_notNamedParty"
  case evSigLink dee >>= sigid emptyNamePlaceholder of
    Just i -> return i
    Nothing -> case evUserID dee of
               Just uid -> if (isAuthor (doc,uid))
                            then authorName emptyNamePlaceholder
                            else do
                              muser <- dbQuery $ GetUserByID uid
                              case muser of
                                Just user -> return $ getSmartName user ++ " (" ++ getEmail user ++ ")"
                                _ -> return "Scrive" -- This should not happend
               _ ->  if (authorEvents $ evType dee)
                        then authorName emptyNamePlaceholder
                        else return "Scrive"

  where authorName emptyNamePlaceholder = case getAuthorSigLink doc >>= sigid emptyNamePlaceholder . signatorylinkid of
                        Just i -> return i
                        Nothing -> renderTemplate_ "_authorParty"
        sigid emptyNamePlaceholder s | tgt == EventForArchive = do
                                             si <- Map.lookup s sim
                                             let name = siFullName si
                                             if null name then
                                                 signatoryIdentifier sim s emptyNamePlaceholder
                                              else
                                                 return name
                                     | otherwise = signatoryIdentifier sim s emptyNamePlaceholder

eventJSValue :: (MonadDB m, MonadThrow m, TemplatesMonad m) => Document -> SignatoryIdentifierMap -> DocumentEvidenceEvent -> JSONGenT m ()
eventJSValue doc sim dee = do
    J.value "status" $ show $ getEvidenceEventStatusClass (evType dee)
    J.value "time"   $ formatTimeISO (evTime dee)
    J.valueM "party" $ approximateActor EventForArchive doc sim dee
    J.valueM "text"  $ simplyfiedEventText EventForArchive Nothing doc sim dee

-- | Simple events to be included in the archive history and the verification page.  These have translations.
simpleEvents :: EvidenceEventType -> Bool
simpleEvents (Current AttachExtendedSealedFileEvidence)  = True
simpleEvents (Current AttachGuardtimeSealedFileEvidence) = True
simpleEvents (Obsolete CancelDocumenElegEvidence)        = True
simpleEvents (Current CancelDocumentEvidence)            = True
simpleEvents (Current InvitationDeliveredByEmail)        = True
simpleEvents (Current InvitationDeliveredBySMS)          = True
simpleEvents (Current InvitationEvidence)                = True
simpleEvents (Current InvitationUndeliveredByEmail)      = True
simpleEvents (Current InvitationUndeliveredBySMS)        = True
simpleEvents (Current MarkInvitationReadEvidence)        = True
simpleEvents (Current PreparationToPendingEvidence)      = True
simpleEvents (Current ProlongDocumentEvidence)           = True
simpleEvents (Current RejectDocumentEvidence)            = True
simpleEvents (Current ReminderSend)                      = True
simpleEvents (Current AutomaticReminderSent)             = True
simpleEvents (Current RestartDocumentEvidence)           = True
simpleEvents (Current SignDocumentEvidence)              = True
simpleEvents (Current SignatoryLinkVisited)              = True
simpleEvents (Current TimeoutDocumentEvidence)           = True
simpleEvents (Current SignWithELegFailureEvidence)       = True
simpleEvents (Current SMSPinSendEvidence)                = True
simpleEvents (Current SMSPinDeliveredEvidence)           = True
simpleEvents _                                           = False

getEvidenceEventStatusClass :: EvidenceEventType -> StatusClass
getEvidenceEventStatusClass (Current CloseDocumentEvidence)             = SCSigned
getEvidenceEventStatusClass (Current CancelDocumentEvidence)            = SCCancelled
getEvidenceEventStatusClass (Current RejectDocumentEvidence)            = SCRejected
getEvidenceEventStatusClass (Current TimeoutDocumentEvidence)           = SCTimedout
getEvidenceEventStatusClass (Current PreparationToPendingEvidence)      = SCInitiated
getEvidenceEventStatusClass (Current MarkInvitationReadEvidence)        = SCRead
getEvidenceEventStatusClass (Current SignatoryLinkVisited)              = SCOpened
getEvidenceEventStatusClass (Current RestartDocumentEvidence)           = SCDraft
getEvidenceEventStatusClass (Current SignDocumentEvidence)              = SCSigned
getEvidenceEventStatusClass (Current InvitationEvidence)                = SCSent
getEvidenceEventStatusClass (Current InvitationDeliveredByEmail)        = SCDelivered
getEvidenceEventStatusClass (Current InvitationUndeliveredByEmail)      = SCDeliveryProblem
getEvidenceEventStatusClass (Current InvitationDeliveredBySMS)          = SCDelivered
getEvidenceEventStatusClass (Current InvitationUndeliveredBySMS)        = SCDeliveryProblem
getEvidenceEventStatusClass (Current ReminderSend)                      = SCSent
getEvidenceEventStatusClass (Current AutomaticReminderSent)             = SCSent
getEvidenceEventStatusClass (Current ResealedPDF)                       = SCSigned
getEvidenceEventStatusClass (Obsolete CancelDocumenElegEvidence)        = SCCancelled
getEvidenceEventStatusClass (Current ProlongDocumentEvidence)           = SCProlonged
getEvidenceEventStatusClass (Current AttachSealedFileEvidence)          = SCSigned
getEvidenceEventStatusClass (Current AttachGuardtimeSealedFileEvidence) = SCSealed
getEvidenceEventStatusClass (Current AttachExtendedSealedFileEvidence)  = SCExtended
getEvidenceEventStatusClass (Current SignWithELegFailureEvidence)       = SCError
getEvidenceEventStatusClass (Current SMSPinSendEvidence)                = SCSent
getEvidenceEventStatusClass (Current SMSPinDeliveredEvidence)           = SCDelivered
getEvidenceEventStatusClass _                                           = SCError

-- Remove signatory events that happen after signing (link visited, invitation read)
cleanUnimportantAfterSigning :: [DocumentEvidenceEvent] -> [DocumentEvidenceEvent]
cleanUnimportantAfterSigning = go Set.empty
  where go _ [] = []
        go m (e:es) | evType e `elem` [Current SignatoryLinkVisited, Current MarkInvitationReadEvidence]
                       && ids e `Set.member` m
                    = go m es -- the only place for skipping events, but these events always have evSigLink == Just ...
                    | evType e == Current SignDocumentEvidence
                    = e : go (Set.insert (ids e) m) es
                    | evType e == Current PreparationToPendingEvidence
                    = e : go Set.empty es
                    | otherwise
                    = e : go m es
        ids e = (evUserID e, evSigLink e)

-- Events that should be considered as performed as author even is actor states different.
authorEvents  :: EvidenceEventType -> Bool
authorEvents (Current PreparationToPendingEvidence) = True
authorEvents _ = False

-- Events that should be considered as performed by the system even if actor states different.
systemEvents  :: EvidenceEventType -> Bool
systemEvents (Current InvitationDeliveredByEmail) = True
systemEvents (Current InvitationUndeliveredByEmail) = True
systemEvents (Current InvitationDeliveredBySMS) = True
systemEvents (Current InvitationUndeliveredBySMS) = True
systemEvents _ = False

-- Empty events - they should be skipped, as they don't provide enought information to show to user
emptyEvent :: DocumentEvidenceEvent -> Bool
emptyEvent (DocumentEvidenceEvent {evType = Current InvitationEvidence, evAffectedSigLink = Nothing }) = True
emptyEvent (DocumentEvidenceEvent {evType = Current ReminderSend,       evAffectedSigLink = Nothing }) = True
emptyEvent _ = False

eventForVerificationPage :: DocumentEvidenceEvent -> Bool
eventForVerificationPage = not . (`elem` map Current [AttachGuardtimeSealedFileEvidence, AttachExtendedSealedFileEvidence]) . evType

-- | Produce simplified text for an event (only for archive or
-- verification pages).
simplyfiedEventText :: (HasLang d, MonadDB m, MonadThrow m, TemplatesMonad m)
  => EventRenderTarget -> Maybe String -> d -> SignatoryIdentifierMap -> DocumentEvidenceEvent -> m String
simplyfiedEventText EventForEvidenceLog _ _ _ _ = $unexpectedErrorM "simplyfiedEventText should not be called for evidence log entries"
simplyfiedEventText target mactor d sim dee = do
  emptyNamePlaceholder <- renderTemplate_ "_notNamedParty"
  case evType dee of
    Obsolete CancelDocumenElegEvidence -> renderEvent emptyNamePlaceholder "CancelDocumenElegEvidenceText"
    Current et -> renderEvent emptyNamePlaceholder $ eventTextTemplateName target et
    Obsolete _ -> return "" -- shouldn't we throw an error in this case?
    where
      render | target == EventForVerificationPages = renderLocalTemplate (getLang d)
             | otherwise                           = renderTemplate
      renderEvent emptyNamePlaceholder eventTemplateName = render eventTemplateName $ do
        let mslinkid = evAffectedSigLink dee
        F.forM_ mslinkid  $ \slinkid -> do
          case Map.lookup slinkid sim >>= siLink of
            Just slink -> do
              signatoryLinkTemplateFields slink
              -- FIXME: fetching email from signatory is not guaranteed to get
              -- the email address field of the signatory at the time of the
              -- event, since the signatory's email may have been updated
              -- later.
              F.value "signatory_email" $ getEmail slink
            Nothing -> do
              -- signatory email: there are events that are missing affected
              -- signatory, but happen to have evEmail set to what we want
              F.value "signatory_email" $ evEmail dee
          -- This is terribad, but another possibility is to include it
          -- in DocumentEvidenceEvent or to include it in SignatoryLink
          -- and none of them are better. The best thing is to think how
          -- to rework evidence log module so that stuff like that can
          -- be somehow painlessly done, I guess.
          when (evType dee == Current SignDocumentEvidence) $ do
            dbQuery (GetESignature slinkid) >>= \case
              Nothing -> return ()
              Just esig -> F.value "eid_signatory_name" $ case esig of
                LegacyBankIDSignature_{} -> Nothing
                LegacyTeliaSignature_{} -> Nothing
                LegacyNordeaSignature_{} -> Nothing
                LegacyMobileBankIDSignature_{} -> Nothing
                BankIDSignature_ BankIDSignature{..} -> Just bidsSignatoryName
        F.value "text" $ String.replace "\n" " " <$> evMessageText dee -- Escape EOL. They are ignored by html and we don't want them on verification page
        F.value "signatory" $ (\slid -> signatoryIdentifier sim slid emptyNamePlaceholder) <$> mslinkid
        F.forM_ mactor $ F.value "actor"

showClockError :: Word8 -> Double -> String
showClockError decimals e = show (realFracToDecimal decimals (e * 1000)) ++ " ms"

-- | Suppress repeated events stemming from mail delivery systems
-- reporting that an email was opened.  This is done by ignoring each
-- such event for five minutes after its last occurrence with the same
-- text.
suppressRepeatedEvents :: [DocumentEvidenceEvent] -> [DocumentEvidenceEvent]
suppressRepeatedEvents = go Map.empty where
  go _ [] = []
  go levs (ev:evs) | evType ev == Current MarkInvitationReadEvidence =
                       if Just (evTime ev) < ((5 `minutesAfter`) <$> Map.lookup (evText ev) levs)
                       then go levs evs
                       else ev : go (Map.insert (evText ev) (evTime ev) levs) evs
                  | otherwise = ev : go levs evs

-- | Generating text of Evidence log that is attached to PDF. It should be complete
htmlDocFromEvidenceLog :: TemplatesMonad m => String -> SignatoryIdentifierMap -> [DocumentEvidenceEvent] -> HC.ClockErrorStatistics -> m String
htmlDocFromEvidenceLog title sim elog ces = do
  emptyNamePlaceholder <- renderTemplate_ "_notNamedParty"
  renderTemplate "htmlevidencelog" $ do
    F.value "documenttitle" title
    F.value "ce_max"       $ showClockError 1 <$> HC.max ces
    F.value "ce_mean"      $ showClockError 1 <$> HC.mean ces
    F.value "ce_std_dev"   $ showClockError 1 <$> HC.std_dev ces
    F.value "ce_collected" $ HC.collected ces
    F.value "ce_missed"    $ HC.missed ces
    F.objects "entries" $ for (filter (not . htmlSkipedEvidenceType . evType) elog) $ \entry -> do
      F.value "time" $ formatTimeUTC (evTime entry) ++ " UTC"
                       ++ maybe "" (\e -> " ±" ++ showClockError 0 e)
                                   (HC.maxClockError (evTime entry) <$> evClockErrorEstimate entry)
      F.value "ces_time" $ maybe "" ((++" UTC") . formatTimeUTC . HC.time)
                                    (evClockErrorEstimate entry)
      F.value "ip"   $ show <$> evIP4 entry
      F.value "text" $ T.unpack $ renderXMLContent $ finalizeEvidenceText sim entry emptyNamePlaceholder

finalizeEvidenceText :: SignatoryIdentifierMap -> DocumentEvidenceEvent -> String -> XMLContent
finalizeEvidenceText sim event emptyNamePlaceholder =
  substitute (Map.fromList [ (("span",n), cdata (T.pack v))
                           | (n,Just v) <- [ ("actor", ((\slid -> signatoryIdentifier sim slid emptyNamePlaceholder) =<< evSigLink event) `mplus` Just (evActor event))
                                           , ("signatory", (\slid -> signatoryIdentifier sim slid emptyNamePlaceholder) =<< evAffectedSigLink event)
                                           , ("author", (\slid -> signatoryIdentifier sim slid emptyNamePlaceholder) =<< authorSigLinkID) ] ]) (evText event)
  where
    authorSigLinkID = signatorylinkid <$> getAuthorSigLink (catMaybes (map siLink (Map.elems sim)))

htmlSkipedEvidenceType :: EvidenceEventType -> Bool
htmlSkipedEvidenceType (Obsolete OldDocumentHistory) = True
htmlSkipedEvidenceType _ = False

-- | Generate evidence of intent in self-contained HTML for inclusion as attachment in PDF.
evidenceOfIntentHTML :: TemplatesMonad m => SignatoryIdentifierMap -> String -> [(SignatoryLink, SignatoryScreenshots.SignatoryScreenshots)] -> m String
evidenceOfIntentHTML sim title l = do
  emptyNamePlaceholder <- renderTemplate_ "_notNamedParty"
  renderTemplate "evidenceOfIntent" $ do
    F.value "documenttitle" title
    let values Nothing = return ()
        values (Just s) = do
          F.value "time" $ formatTimeUTC (Screenshot.time s) ++ " UTC"
          F.value "image" $ imgEncodeRFC2397 $ unBinary $ Screenshot.image s
    F.objects "entries" $ for l $ \(sl, entry) -> do
      F.value "signatory"  $ signatoryIdentifier sim (signatorylinkid sl) emptyNamePlaceholder
      F.value "ip"         $ show . signipnumber <$> maybesigninfo sl
      F.object "first"     $ values (SignatoryScreenshots.first entry)
      F.object "signing"   $ values (SignatoryScreenshots.signing entry)
      F.object "reference" $ values (SignatoryScreenshots.getReferenceScreenshot entry)
