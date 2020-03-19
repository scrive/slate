module EID.EIDService.Control (
    eidServiceRoutes
  ) where

import Data.Aeson ((.=), Value, object)
import Happstack.Server hiding (Expired, dir)
import Happstack.StaticRouting
import Log
import Network.HTTP.Base (urlEncode)
import Text.StringTemplates.Templates
import qualified Data.ByteString.Base64 as B64
import qualified Data.ByteString.Char8 as BSC8
import qualified Data.Text as T
import qualified Data.Text.Encoding as T
import qualified Text.StringTemplates.Fields as F

import Analytics.Include
import AppView
import Chargeable
import DB
import Doc.DocStateData
import Doc.DocStateQuery
import Doc.DocumentID
import Doc.DocumentMonad
import Doc.DocUtils
import Doc.Model.Query
import Doc.Model.Update
import Doc.SignatoryLinkID
import EID.Authentication.Model
import EID.EIDService.Communication
import EID.EIDService.Conf
import EID.EIDService.Model
import EID.EIDService.Types
import EvidenceLog.Model
import FlashMessage
import Happstack.Fields
import InputValidation (asValidPhoneForNorwegianBankID, resultToMaybe)
import Kontra hiding (InternalError)
import MinutesTime
import Routing
import Session.Model
import Session.SessionID
import Templates (renderTextTemplate)
import User.Lang
import UserGroup.Model
import UserGroup.Types
import Util.Actor
import Util.HasSomeUserInfo
import Util.MonadUtils
import Util.SignatoryLinkUtils

eidServiceRoutes :: Route (Kontra Response)
eidServiceRoutes = choice
  [ (dir "start" . dir "verimi" . hPost . toK2) startVerimiEIDServiceTransaction
  , (dir "redirect-endpoint" . dir "verimi" . hGet . toK2)
    redirectEndpointFromVerimiEIDServiceTransaction
  , (dir "start" . dir "idin-view" . hPost . toK2) startIDINViewEIDServiceTransaction
  , (dir "redirect-endpoint" . dir "idin-view" . hGet . toK2)
    redirectEndpointFromIDINViewEIDServiceTransaction
  , (dir "start" . dir "idin-sign" . hPost . toK2) startIDINSignEIDServiceTransaction
  , (dir "redirect-endpoint" . dir "idin-sign" . hGet . toK2)
    redirectEndpointFromIDINSignEIDServiceTransaction
  , (dir "start" . dir "nemid" . hPost . toK2) startNemIDViewEIDServiceTransaction
  , (dir "redirect-endpoint" . dir "nemid-view" . hGet . toK2)
    redirectEndpointFromNemIDViewEIDServiceTransaction
  , (dir "start" . dir "nobankid-view" . hPost . toK2)
    startNOBankIDViewEIDServiceTransaction
  , (dir "redirect-endpoint" . dir "nobankid-view" . hGet . toK2)
    redirectEndpointFromNOBankIDViewEIDServiceTransaction
  , (dir "start" . dir "fitupas-sign" . hPost . toK2)
    startFITupasSignEIDServiceTransaction
  , (dir "redirect-endpoint" . dir "fitupas-sign" . hGet . toK2)
    redirectEndpointFromFITupasSignEIDServiceTransaction
  ]

eidServiceConf :: Kontrakcja m => Document -> m EIDServiceConf
eidServiceConf doc = do
  ctx <- getContext
  case ctx ^. #eidServiceConf of
    Nothing    -> noConfigurationError "No eid service provided"
    Just conf0 -> do
      let err =
            unexpectedError $ "Impossible happened - no author for document: " <> showt
              (documentid doc)
      authorid <- maybe err return $ maybesignatory =<< getAuthorSigLink doc
      ugwp     <- dbQuery . UserGroupGetWithParentsByUserID $ authorid
      return $ case ugwpSettings ugwp ^. #eidServiceToken of
        Nothing    -> conf0
        Just token -> set #eidServiceToken token conf0

startVerimiEIDServiceTransaction
  :: Kontrakcja m => DocumentID -> SignatoryLinkID -> m Value
startVerimiEIDServiceTransaction did slid = do
  logInfo_ "EID Service transaction start - for Verimi view"
  (doc, sl) <- getDocumentAndSignatoryForEIDAuth did slid -- also access guard
  startEIDServiceTransaction doc
                             sl
                             (EIDServiceAuthToView $ mkAuthKind doc)
                             EIDServiceTransactionProviderVerimi

startIDINViewEIDServiceTransaction
  :: Kontrakcja m => DocumentID -> SignatoryLinkID -> m Value
startIDINViewEIDServiceTransaction did slid = do
  logInfo_ "EID Service transaction start - for iDIN view"
  (doc, sl) <- getDocumentAndSignatoryForEIDAuth did slid -- also access guard
  startEIDServiceTransaction doc
                             sl
                             (EIDServiceAuthToView $ mkAuthKind doc)
                             EIDServiceTransactionProviderNLIDIN

startIDINSignEIDServiceTransaction
  :: Kontrakcja m => DocumentID -> SignatoryLinkID -> m Value
startIDINSignEIDServiceTransaction did slid = do
  logInfo_ "EID Service transaction start - for iDIN sign"
  (doc, sl) <- getDocumentAndSignatoryForEIDAuth did slid -- also access guard
  startEIDServiceTransaction doc
                             sl
                             EIDServiceAuthToSign
                             EIDServiceTransactionProviderNLIDIN

startNemIDViewEIDServiceTransaction
  :: Kontrakcja m => DocumentID -> SignatoryLinkID -> m Value
startNemIDViewEIDServiceTransaction did slid = do
  logInfo_ "EID Service transaction start - for NemID view"
  (doc, sl) <- getDocumentAndSignatoryForEIDAuth did slid -- also access guard
  startEIDServiceTransaction doc
                             sl
                             (EIDServiceAuthToView $ mkAuthKind doc)
                             EIDServiceTransactionProviderDKNemID

startNOBankIDViewEIDServiceTransaction
  :: Kontrakcja m => DocumentID -> SignatoryLinkID -> m Value
startNOBankIDViewEIDServiceTransaction did slid = do
  logInfo_ "EID Service transaction start - for NOBankID view"
  (doc, sl) <- getDocumentAndSignatoryForEIDAuth did slid -- also access guard
  startEIDServiceTransaction doc
                             sl
                             (EIDServiceAuthToView $ mkAuthKind doc)
                             EIDServiceTransactionProviderNOBankID

startFITupasSignEIDServiceTransaction
  :: Kontrakcja m => DocumentID -> SignatoryLinkID -> m Value
startFITupasSignEIDServiceTransaction did slid = do
  logInfo_ "EID Service transaction start - for FITupas sign"
  (doc, sl) <- getDocumentAndSignatoryForEIDAuth did slid -- also access guard
  startEIDServiceTransaction doc
                             sl
                             EIDServiceAuthToSign
                             EIDServiceTransactionProviderFITupas

-- TODO: construction of redirect URL should be handled by JSON module
makeRedirectURL
  :: Kontrakcja m
  => Document
  -> SignatoryLink
  -> EIDServiceAuthenticationKind
  -> EIDServiceTransactionProvider
  -> m Text
makeRedirectURL doc sl eidserviceAuthKind provider = do
  ctx        <- getContext
  rdFragment <- case eidserviceAuthKind of
    EIDServiceAuthToView _ -> do
      -- TODO: Why are we getting this redirect from the frontend in the first place?
      rd <- guardJustM $ getField "redirect"
      return $ "?redirect=" <> rd
    EIDServiceAuthToSign -> return ""
  return
    $  (ctx ^. #brandedDomain % #url)
    <> "/eid-service/redirect-endpoint/"
    <> redirectFragment
    <> "/"
    <> showt (documentid doc)
    <> "/"
    <> showt (signatorylinkid sl)
    <> rdFragment
  where
    redirectFragment = case (provider, eidserviceAuthKind) of
      (EIDServiceTransactionProviderNLIDIN{}, EIDServiceAuthToView _) -> "idin-view"
      (EIDServiceTransactionProviderNLIDIN{}  , EIDServiceAuthToSign) -> "idin-sign"
      (EIDServiceTransactionProviderFITupas{}, EIDServiceAuthToView _) -> "fitupas-view"
      (EIDServiceTransactionProviderFITupas{} , EIDServiceAuthToSign) -> "fitupas-sign"
      (EIDServiceTransactionProviderVerimi{}  , _                   ) -> "verimi"
      (EIDServiceTransactionProviderDKNemID{} , _                   ) -> "nemid-view"
      (EIDServiceTransactionProviderNOBankID{}, _                   ) -> "nobankid-view"

startEIDServiceTransaction
  :: Kontrakcja m
  => Document
  -> SignatoryLink
  -> EIDServiceAuthenticationKind
  -> EIDServiceTransactionProvider
  -> m Value
startEIDServiceTransaction doc sl eidserviceAuthKind provider = do
  -- TODO: This function should be broken up into logical tasks
  conf           <- eidServiceConf doc
  redirectUrl    <- makeRedirectURL doc sl eidserviceAuthKind provider
  providerParams <- case provider of
    EIDServiceTransactionProviderNLIDIN ->
      return EIDServiceProviderParamsNLIDIN { esppRedirectURL = redirectUrl }
    EIDServiceTransactionProviderVerimi ->
      return EIDServiceProviderParamsVerimi { esppRedirectURL = redirectUrl }
    EIDServiceTransactionProviderDKNemID -> do
      let locale = case documentlang doc of
            LANG_SV -> "sv-SE"
            LANG_NO -> "nb-NO"
            LANG_DA -> "da-DK"
            _       -> "en-GB"
      return EIDServiceProviderParamsDKNemID { esppRedirectURL = redirectUrl
                                             , esppUILocale    = locale
                                             }
    EIDServiceTransactionProviderNOBankID -> do
      personalNumberField <-
        guardJust . getFieldByIdentity PersonalNumberFI . signatoryfields $ sl
      ssn <- guardJust . fieldTextValue $ personalNumberField
      let mNonEmptyNOPhone = case getMobile sl of
            "" -> Nothing
            p  -> resultToMaybe . asValidPhoneForNorwegianBankID $ p
      return EIDServiceProviderParamsNOBankID { esppRedirectURL    = redirectUrl
                                              , esppPhoneNumber    = mNonEmptyNOPhone
                                              , esppPersonalNumber = ssn
                                              }
    EIDServiceTransactionProviderFITupas ->
      return EIDServiceProviderParamsFITupas { esppRedirectURL = redirectUrl }
  tid  <- createTransactionWithEIDService conf providerParams
  turl <- startTransactionWithEIDService conf provider tid
  sid  <- getNonTempSessionID
  now  <- currentTime
  let newTransaction = EIDServiceTransaction
        { estID              = tid
        , estStatus          = EIDServiceTransactionStatusStarted
        , estSignatoryLinkID = signatorylinkid sl
        , estAuthKind        = eidserviceAuthKind
        , estProvider        = provider
        , estSessionID       = sid
        , estDeadline        = 60 `minutesAfter` now
        }
  dbUpdate $ MergeEIDServiceTransaction newTransaction
  return $ object ["accessUrl" .= turl]

updateVerimiTransactionAfterCheck
  :: Kontrakcja m
  => SignatoryLinkID
  -> EIDServiceTransaction
  -> EIDServiceTransactionStatus
  -> Maybe CompleteVerimiEIDServiceTransactionData
  -> m EIDServiceTransactionStatus
updateVerimiTransactionAfterCheck slid est ts mctd = do
  if estStatus est == ts
    then return $ estStatus est
    else do
      case (ts, mctd) of
        (EIDServiceTransactionStatusCompleteAndSuccess, Just cd) -> do
          doc <- dbQuery $ GetDocumentBySignatoryLinkID slid
          let sl = fromJust $ getSigLinkFor slid doc
          if eidvtdVerifiedEmail cd == getEmail sl
            then do
              mergeEIDServiceTransactionWithStatus
                EIDServiceTransactionStatusCompleteAndSuccess
              let auth = EIDServiceVerimiAuthentication
                    { eidServiceVerimiName          = eidvtdName cd
                    , eidServiceVerimiVerifiedEmail = Just $ eidvtdVerifiedEmail cd
                    , eidServiceVerimiVerifiedPhone = Nothing
                    }
              sessionID <- getNonTempSessionID
              dbUpdate $ MergeEIDServiceVerimiAuthentication (mkAuthKind doc)
                                                             sessionID
                                                             slid
                                                             auth
              ctx <- getContext
              let eventFields = do
                    F.value "signatory_name" $ eidvtdName cd
                    F.value "provider_verimi" True
              withDocument doc $ do
                void
                  $   dbUpdate
                  .   InsertEvidenceEventWithAffectedSignatoryAndMsg
                        AuthenticatedToViewEvidence
                        eventFields
                        (Just sl)
                        Nothing
                  =<< signatoryActor ctx sl
                chargeForItemSingle CIVerimiAuthentication $ documentid doc
              return EIDServiceTransactionStatusCompleteAndSuccess
            else do
              mergeEIDServiceTransactionWithStatus
                EIDServiceTransactionStatusCompleteAndFailed
              return EIDServiceTransactionStatusCompleteAndFailed
        (EIDServiceTransactionStatusCompleteAndSuccess, Nothing) -> do
          mergeEIDServiceTransactionWithStatus
            EIDServiceTransactionStatusCompleteAndFailed
          return EIDServiceTransactionStatusCompleteAndFailed
        _ -> do
          mergeEIDServiceTransactionWithStatus ts
          return ts
  where
    mergeEIDServiceTransactionWithStatus newstatus =
      dbUpdate . MergeEIDServiceTransaction $ est { estStatus = newstatus }

checkVerimiEIDServiceTransactionForSignatory
  :: Kontrakcja m
  => SignatoryLinkID
  -> m
       ( Maybe
           ( EIDServiceTransaction
           , EIDServiceTransactionStatus
           , Maybe CompleteVerimiEIDServiceTransactionData
           )
       )
checkVerimiEIDServiceTransactionForSignatory slid = do
  sessionID <- getNonTempSessionID
  doc       <- dbQuery $ GetDocumentBySignatoryLinkID slid
  conf      <- eidServiceConf doc
  mest      <- dbQuery $ GetEIDServiceTransactionGuardSessionID
    sessionID
    slid
    (EIDServiceAuthToView $ mkAuthKind doc)
  case mest of
    Nothing -> return Nothing
    Just est ->
      getTransactionFromEIDService conf EIDServiceTransactionProviderVerimi (estID est)
        >>= \case
              (Nothing, _   ) -> return Nothing
              (Just ts, mctd) -> return $ Just (est, ts, mctd)

redirectEndpointFromVerimiEIDServiceTransaction
  :: Kontrakcja m => DocumentID -> SignatoryLinkID -> m Response
redirectEndpointFromVerimiEIDServiceTransaction did slid = do
  logInfo_ "EID Service transaction check"
  void $ getDocumentAndSignatoryForEIDAuth did slid -- access guard
  ad  <- getAnalyticsData
  ctx <- getContext
  rd  <- guardJustM $ getField "redirect"
  res <- checkVerimiEIDServiceTransactionForSignatory slid
  mts <- case res of
    Just (est, ts, mctd) -> do
      nts <- updateVerimiTransactionAfterCheck slid est ts mctd
      return $ Just nts
    _ -> return Nothing
  redirectPage <- renderTextTemplate "postVerimiRedirect" $ do
    F.value "redirect" rd
    F.value "incorrect_data" (mts == Just EIDServiceTransactionStatusCompleteAndFailed)
    standardPageFields ctx Nothing ad
  simpleHtmlResponse redirectPage

redirectEndpointFromFITupasSignEIDServiceTransaction
  :: Kontrakcja m => DocumentID -> SignatoryLinkID -> m Response
redirectEndpointFromFITupasSignEIDServiceTransaction did slid = do
  logInfo_ "EID Service signing transaction check"
  doc       <- fst <$> getDocumentAndSignatoryForEIDAuth did slid -- access guard
  ad        <- getAnalyticsData
  ctx       <- getContext
  conf      <- eidServiceConf doc
  sessionID <- getNonTempSessionID
  res       <- checkFITupasEIDServiceTransactionForSignatoryWithConf conf
                                                                     slid
                                                                     sessionID
                                                                     EIDServiceAuthToSign
  sl <- dbQuery $ GetSignatoryLinkByID did slid
  let redirectUrl = "/s/" <> show did <> "/" <> show slid
      correctData
        | Just (_, EIDServiceTransactionStatusCompleteAndSuccess, Just cd) <- res
        = T.null (getPersonalNumber sl)
          || isNothing (eidtupasSSN cd)
          || (getPersonalNumber sl == fromMaybe "" (eidtupasSSN cd))
        | otherwise
        = False  -- the transaction cannot be just New or Started now,
                             -- we were redirected here at the end of EID Auth

  redirectPage <- renderTextTemplate "postFITupasSignRedirect" $ do
    F.value "redirect" . B64.encode . BSC8.pack . urlEncode $ redirectUrl
    F.value "incorrect_data" $ not correctData
    F.value "document_id" $ show did
    F.value "signatory_link_id" $ show slid
    standardPageFields ctx Nothing ad
  simpleHtmlResponse redirectPage

checkFITupasEIDServiceTransactionForSignatoryWithConf
  :: Kontrakcja m
  => EIDServiceConf
  -> SignatoryLinkID
  -> SessionID
  -> EIDServiceAuthenticationKind
  -> m
       ( Maybe
           ( EIDServiceTransaction
           , EIDServiceTransactionStatus
           , Maybe CompleteFITupasEIDServiceTransactionData
           )
       )
checkFITupasEIDServiceTransactionForSignatoryWithConf conf slid sessionID eidAuthKind =
  do
    mest <- dbQuery $ GetEIDServiceTransactionGuardSessionID sessionID slid eidAuthKind
    case mest of
      Nothing -> return Nothing
      Just est ->
        getTransactionFromEIDService conf EIDServiceTransactionProviderFITupas (estID est)
          >>= \case
                (Nothing, _   ) -> return Nothing
                (Just ts, mctd) -> return $ Just (est, ts, mctd)

updateIDINTransactionAfterCheck
  :: Kontrakcja m
  => SignatoryLinkID
  -> EIDServiceTransaction
  -> EIDServiceTransactionStatus
  -> Maybe CompleteNLIDINEIDServiceTransactionData
  -> m EIDServiceTransactionStatus
updateIDINTransactionAfterCheck slid est ts mctd = do
  if estStatus est == ts
    then return $ estStatus est
    else do
      case (ts, mctd) of
        (EIDServiceTransactionStatusCompleteAndSuccess, Just cd) -> do
          doc <- dbQuery $ GetDocumentBySignatoryLinkID slid
          let sl = fromJust $ getSigLinkFor slid doc
          mergeEIDServiceTransactionWithStatus
            EIDServiceTransactionStatusCompleteAndSuccess
          let auth = EIDServiceNLIDINAuthentication
                { eidServiceIDINName          = eiditdName cd
                , eidServiceIDINVerifiedPhone = Nothing
                , eidServiceIDINBirthDate     = Just $ eiditdBirthDate cd
                , eidServiceIDINCustomerID    = Just $ eiditdCustomerID cd
                }
          sessionID <- getNonTempSessionID
          dbUpdate
            $ MergeEIDServiceIDINAuthentication (mkAuthKind doc) sessionID slid auth
          ctx <- getContext
          let eventFields = do
                F.value "signatory_name" $ eiditdName cd
                F.value "provider_idin" True
          withDocument doc $ do
            void
              $   dbUpdate
              .   InsertEvidenceEventWithAffectedSignatoryAndMsg
                    AuthenticatedToViewEvidence
                    eventFields
                    (Just sl)
                    Nothing
              =<< signatoryActor ctx sl
            chargeForItemSingle CIIDINAuthentication $ documentid doc
          return EIDServiceTransactionStatusCompleteAndSuccess
        (EIDServiceTransactionStatusCompleteAndSuccess, Nothing) -> do
          mergeEIDServiceTransactionWithStatus
            EIDServiceTransactionStatusCompleteAndFailed
          return EIDServiceTransactionStatusCompleteAndFailed
        _ -> do
          mergeEIDServiceTransactionWithStatus ts
          return ts
  where
    mergeEIDServiceTransactionWithStatus newstatus =
      dbUpdate . MergeEIDServiceTransaction $ est { estStatus = newstatus }

checkIDINEIDServiceTransactionForSignatory
  :: Kontrakcja m
  => Document
  -> SignatoryLinkID
  -> EIDServiceAuthenticationKind
  -> m
       ( Maybe
           ( EIDServiceTransaction
           , EIDServiceTransactionStatus
           , Maybe CompleteNLIDINEIDServiceTransactionData
           )
       )
checkIDINEIDServiceTransactionForSignatory doc slid eidserviceAuthKind = do
  conf      <- eidServiceConf doc
  sessionID <- getNonTempSessionID
  checkIDINEIDServiceTransactionForSignatoryWithConf conf
                                                     slid
                                                     sessionID
                                                     eidserviceAuthKind

checkIDINEIDServiceTransactionForSignatoryWithConf
  :: Kontrakcja m
  => EIDServiceConf
  -> SignatoryLinkID
  -> SessionID
  -> EIDServiceAuthenticationKind
  -> m
       ( Maybe
           ( EIDServiceTransaction
           , EIDServiceTransactionStatus
           , Maybe CompleteNLIDINEIDServiceTransactionData
           )
       )
checkIDINEIDServiceTransactionForSignatoryWithConf conf slid sessionID eidAuthKind = do
  mest <- dbQuery $ GetEIDServiceTransactionGuardSessionID sessionID slid eidAuthKind
  case mest of
    Nothing -> return Nothing
    Just est ->
      getTransactionFromEIDService conf EIDServiceTransactionProviderNLIDIN (estID est)
        >>= \case
              (Nothing, _   ) -> return Nothing
              (Just ts, mctd) -> return $ Just (est, ts, mctd)

redirectEndpointFromIDINViewEIDServiceTransaction
  :: Kontrakcja m => DocumentID -> SignatoryLinkID -> m Response
redirectEndpointFromIDINViewEIDServiceTransaction did slid = do
  logInfo_ "EID Service transaction check"
  void $ getDocumentAndSignatoryForEIDAuth did slid -- access guard
  ad  <- getAnalyticsData
  ctx <- getContext
  rd  <- guardJustM $ getField "redirect"
  doc <- dbQuery $ GetDocumentBySignatoryLinkID slid
  res <-
    checkIDINEIDServiceTransactionForSignatory doc slid
    . EIDServiceAuthToView
    $ mkAuthKind doc
  mts <- case res of
    Just (est, ts, mctd) -> do
      nts <- updateIDINTransactionAfterCheck slid est ts mctd
      return $ Just nts
    _ -> return Nothing
  redirectPage <- renderTextTemplate "postIDINViewRedirect" $ do
    F.value "redirect" rd
    F.value "incorrect_data" (mts == Just EIDServiceTransactionStatusCompleteAndFailed)
    standardPageFields ctx Nothing ad
  simpleHtmlResponse redirectPage

redirectEndpointFromIDINSignEIDServiceTransaction
  :: Kontrakcja m => DocumentID -> SignatoryLinkID -> m Response
redirectEndpointFromIDINSignEIDServiceTransaction did slid = do
  logInfo_ "EID Service signing transaction check"
  doc       <- fst <$> getDocumentAndSignatoryForEIDAuth did slid -- access guard
  ad        <- getAnalyticsData
  ctx       <- getContext
  conf      <- eidServiceConf doc
  sessionID <- getNonTempSessionID
  res       <- checkIDINEIDServiceTransactionForSignatoryWithConf conf
                                                                  slid
                                                                  sessionID
                                                                  EIDServiceAuthToSign

  let redirectUrl = "/s/" <> show did <> "/" <> show slid
      correctData = case res of
        Just (_, EIDServiceTransactionStatusCompleteAndSuccess, Just _cd) -> True
        -- the transaction cannot be just New or Started now,
        -- we were redirected here at the end of EID Auth
        _ -> False
  redirectPage <- renderTextTemplate "postIDINSignRedirect" $ do
    F.value "redirect" . B64.encode . BSC8.pack . urlEncode $ redirectUrl
    F.value "incorrect_data" $ not correctData
    F.value "document_id" $ show did
    F.value "signatory_link_id" $ show slid
    standardPageFields ctx Nothing ad
  simpleHtmlResponse redirectPage

updateNemIDTransactionAfterCheck
  :: Kontrakcja m
  => SignatoryLinkID
  -> EIDServiceTransaction
  -> EIDServiceTransactionStatus
  -> Maybe CompleteDKNemIDEIDServiceTransactionData
  -> m EIDServiceTransactionStatus
updateNemIDTransactionAfterCheck slid est ts mctd = do
  if estStatus est == ts
    then return $ estStatus est
    else do
      case (ts, mctd) of
        (EIDServiceTransactionStatusCompleteAndSuccess, Just cd) -> do
          doc <- dbQuery $ GetDocumentBySignatoryLinkID slid
          let signatoryLink = fromJust $ getSigLinkFor slid doc
          mergeEIDServiceTransactionWithStatus
            EIDServiceTransactionStatusCompleteAndSuccess
          let ssnFromEIDService    = normalizeSSN $ eidnidSSN cd
              ssnFromSignatoryLink = normalizeSSN $ getPersonalNumber signatoryLink
          if ssnFromEIDService /= ssnFromSignatoryLink
            then do
              logAttention "SSN from NETS does not match SSN from SignatoryLink." $ object
                [ "ssn_sl" .= ssnFromSignatoryLink
                , "ssn_eidhub" .= ssnFromEIDService
                , "provider" .= ("dk_nemid" :: Text)
                ]
              flashMessageUserHasIdentifiedWithDifferentSSN
                >>= addFlashCookie
                .   toCookieValue
              return EIDServiceTransactionStatusCompleteAndFailed
            else do
              let signatoryName = cnFromDN $ eidnidDistinguishedName cd
                  birthDate     = eidnidBirthDate cd
                  certificate   = decodeCertificate $ eidnidCertificate cd
                  auth          = EIDServiceDKNemIDAuthentication
                    { eidServiceNemIDInternalProvider = eidnidInternalProvider cd
                    , eidServiceNemIDSignatoryName    = signatoryName
                    , eidServiceNemIDDateOfBirth      = birthDate
                    , eidServiceNemIDCertificate      = certificate
                    }
              sessionID <- getNonTempSessionID
              dbUpdate $ MergeEIDServiceNemIDAuthentication (mkAuthKind doc)
                                                            sessionID
                                                            slid
                                                            auth
              ctx <- getContext
              let pid         = eidnidPid cd
                  eventFields = do
                    F.value "signatory_name" signatoryName
                    F.value "provider_dknemid" True
                    F.value "signatory_dob" birthDate
                    F.value "signatory_pid" pid
                    F.value "signature" $ B64.encode certificate
              withDocument doc $ do
                when (mkAuthKind doc == AuthenticationToView) $ do
                  void
                    $   dbUpdate
                    .   InsertEvidenceEventWithAffectedSignatoryAndMsg
                          AuthenticatedToViewEvidence
                          eventFields
                          (Just signatoryLink)
                          Nothing
                    =<< signatoryActor ctx signatoryLink
                chargeForItemSingle CIDKNemIDAuthentication $ documentid doc
              return EIDServiceTransactionStatusCompleteAndSuccess
        (EIDServiceTransactionStatusCompleteAndSuccess, Nothing) -> do
          mergeEIDServiceTransactionWithStatus
            EIDServiceTransactionStatusCompleteAndFailed
          return EIDServiceTransactionStatusCompleteAndFailed
        _ -> do
          mergeEIDServiceTransactionWithStatus ts
          return ts
  where
    mergeEIDServiceTransactionWithStatus newstatus =
      dbUpdate . MergeEIDServiceTransaction $ est { estStatus = newstatus }
    decodeCertificate :: Text -> BSC8.ByteString
    decodeCertificate =
      either (unexpectedError "invalid base64 of NemID certificate") identity
        . B64.decode
        . T.encodeUtf8
    cnFromDN :: Text -> Text
    cnFromDN dn = fromMaybe parseError . lookup "CN" $ fmap
      parsePair
      (concatMap (T.splitOn " + ") $ T.splitOn ", " dn)
      where
        parsePair s = case T.splitOn "=" s of
          (name : values) -> (name, T.intercalate "=" values)
          _               -> unexpectedError $ "Cannot parse DN value: " <> dn
        parseError = unexpectedError $ "Cannot parse DN value: " <> dn
    normalizeSSN :: Text -> Text
    normalizeSSN = T.filter (/= '-')
    flashMessageUserHasIdentifiedWithDifferentSSN :: TemplatesMonad m => m FlashMessage
    flashMessageUserHasIdentifiedWithDifferentSSN = toFlashMsg OperationFailed
      <$> renderTemplate_ "flashMessageUserHasIdentifiedWithDifferentSSN"

redirectEndpointFromNemIDViewEIDServiceTransaction
  :: Kontrakcja m => DocumentID -> SignatoryLinkID -> m Response
redirectEndpointFromNemIDViewEIDServiceTransaction did slid = do
  logInfo_ "EID Service transaction check"
  void $ getDocumentAndSignatoryForEIDAuth did slid -- access guard
  ad  <- getAnalyticsData
  ctx <- getContext
  rd  <- guardJustM $ getField "redirect"
  res <- checkNemIDEIDServiceTransactionForSignatory
  mts <- case res of
    Just (est, ts, mctd) -> do
      nts <- updateNemIDTransactionAfterCheck slid est ts mctd
      return $ Just nts
    _ -> return Nothing
  redirectPage <- renderTextTemplate "postNemIDRedirect" $ do
    F.value "redirect" rd
    F.value "incorrect_data" (mts == Just EIDServiceTransactionStatusCompleteAndFailed)
    standardPageFields ctx Nothing ad
  simpleHtmlResponse redirectPage
  where
    checkNemIDEIDServiceTransactionForSignatory
      :: Kontrakcja m
      => m
           ( Maybe
               ( EIDServiceTransaction
               , EIDServiceTransactionStatus
               , Maybe CompleteDKNemIDEIDServiceTransactionData
               )
           )
    checkNemIDEIDServiceTransactionForSignatory = do
      sessionID <- getNonTempSessionID
      doc       <- dbQuery $ GetDocumentBySignatoryLinkID slid
      conf      <- eidServiceConf doc
      mest      <- dbQuery $ GetEIDServiceTransactionGuardSessionID
        sessionID
        slid
        (EIDServiceAuthToView $ mkAuthKind doc)
      case mest of
        Nothing -> return Nothing
        Just est ->
          getTransactionFromEIDService conf
                                       EIDServiceTransactionProviderDKNemID
                                       (estID est)
            >>= \case
                  (Nothing, _   ) -> return Nothing
                  (Just ts, mctd) -> return $ Just (est, ts, mctd)

redirectEndpointFromNOBankIDViewEIDServiceTransaction
  :: Kontrakcja m => DocumentID -> SignatoryLinkID -> m Response
redirectEndpointFromNOBankIDViewEIDServiceTransaction did slid = do
  logInfo_ "EID Service transaction check"
  void $ getDocumentAndSignatoryForEIDAuth did slid -- access guard
  ad  <- getAnalyticsData
  ctx <- getContext
  rd  <- guardJustM $ getField "redirect"
  res <- checkNOBankIDEIDServiceTransactionForSignatory
  mts <- case res of
    Just (est, ts, mctd) -> do
      nts <- updateNOBankIDTransactionAfterCheck slid est ts mctd
      return $ Just nts
    _ -> return Nothing
  redirectPage <- renderTextTemplate "postNOBankIDRedirect" $ do
    F.value "redirect" rd
    F.value "incorrect_data" (mts == Just EIDServiceTransactionStatusCompleteAndFailed)
    standardPageFields ctx Nothing ad
  simpleHtmlResponse redirectPage
  where
    checkNOBankIDEIDServiceTransactionForSignatory
      :: Kontrakcja m
      => m
           ( Maybe
               ( EIDServiceTransaction
               , EIDServiceTransactionStatus
               , Maybe CompleteNOBankIDEIDServiceTransactionData
               )
           )
    checkNOBankIDEIDServiceTransactionForSignatory = do
      sessionID <- getNonTempSessionID
      doc       <- dbQuery $ GetDocumentBySignatoryLinkID slid
      conf      <- eidServiceConf doc
      mest      <- dbQuery $ GetEIDServiceTransactionGuardSessionID
        sessionID
        slid
        (EIDServiceAuthToView $ mkAuthKind doc)
      case mest of
        Nothing -> return Nothing
        Just est ->
          getTransactionFromEIDService conf
                                       EIDServiceTransactionProviderNOBankID
                                       (estID est)
            >>= \case
                  (Nothing, _   ) -> return Nothing
                  (Just ts, mctd) -> return $ Just (est, ts, mctd)

updateNOBankIDTransactionAfterCheck
  :: Kontrakcja m
  => SignatoryLinkID
  -> EIDServiceTransaction
  -> EIDServiceTransactionStatus
  -> Maybe CompleteNOBankIDEIDServiceTransactionData
  -> m EIDServiceTransactionStatus
updateNOBankIDTransactionAfterCheck slid est ts mctd = do
  if estStatus est == ts
    then return $ estStatus est
    else do
      case (ts, mctd) of
        (EIDServiceTransactionStatusCompleteAndSuccess, Just cd) -> do
          doc <- dbQuery $ GetDocumentBySignatoryLinkID slid
          let signatoryLink = fromJust $ getSigLinkFor slid doc
          mergeEIDServiceTransactionWithStatus
            EIDServiceTransactionStatusCompleteAndSuccess
          let mDobFromEIDService = eidnobidBirthDate cd
              dobFromSignatoryLink =
                resolveDateOfBirthFromSSN $ getPersonalNumber signatoryLink
              mNameFromEIDService = eidnobidName cd
          if isNothing mDobFromEIDService
            then do
              logAttention_ "Distinguished name not provided by EIDService."
              flashErrWithMessage
                =<< renderTemplate_ "flashMessageNoDOBProvidedByEIDService"
              return EIDServiceTransactionStatusCompleteAndFailed
            else if isNothing mNameFromEIDService
              then do
                logAttention_ "Name not provided by EIDService."
                flashErrWithMessage
                  =<< renderTemplate_ "flashMessageNoNameProvidedByEIDService"
                return EIDServiceTransactionStatusCompleteAndFailed
              else if mDobFromEIDService /= Just dobFromSignatoryLink
                then do
                  logAttention
                      "Date of birth from EIDService does not match the one from SignatoryLink."
                    $ object
                        [ "dob_sl" .= dobFromSignatoryLink
                        , "dob_eidhub" .= mDobFromEIDService
                        , "provider" .= ("no_nobankid" :: Text)
                        ]
                  flashErrWithMessage
                    =<< renderTemplate_ "flashMessageUserHasIdentifiedWithDifferentSSN"
                  return EIDServiceTransactionStatusCompleteAndFailed
                else do
                  signatoryName <- guardJust $ eidnobidName cd
                  birthDate     <- guardJust mDobFromEIDService
                  let certificate      = decodeCertificate <$> eidnobidCertificate cd
                      phoneNumber      = eidnobidPhoneNumber cd
                      internalProvider = eidnobidInternalProvider cd
                      auth             = EIDServiceNOBankIDAuthentication
                        { eidServiceNOBankIDInternalProvider = internalProvider
                        , eidServiceNOBankIDSignatoryName    = signatoryName
                        , eidServiceNOBankIDPhoneNumber      = phoneNumber
                        , eidServiceNOBankIDDateOfBirth      = birthDate
                        , eidServiceNOBankIDCertificate      = certificate
                        }
                  sessionID <- getNonTempSessionID
                  dbUpdate $ MergeEIDServiceNOBankIDAuthentication (mkAuthKind doc)
                                                                   sessionID
                                                                   slid
                                                                   auth
                  ctx <- getContext
                  let pid         = eidnobidPid cd
                      signatoryDN = eidnobidDistinguishedName cd
                      issuerDN    = eidnobidIssuerDistinguishedName cd
                      eventFields = do
                        F.value "signatory_name" signatoryName
                        F.value "signatory_mobile" phoneNumber
                        F.value "provider_nobankid_eidservice" True
                        F.value "signatory_dob" birthDate
                        F.value "signatory_pid" pid
                        F.value "signatory_distinguished_name" signatoryDN
                        F.value "issuer_distinguished_name" issuerDN
                        F.value "signature" $ B64.encode <$> certificate
                  withDocument doc $ do
                    actor <- signatoryActor ctx signatoryLink
                    when (mkAuthKind doc == AuthenticationToView) $ do
                      void
                        . dbUpdate
                        . InsertEvidenceEventWithAffectedSignatoryAndMsg
                            AuthenticatedToViewEvidence
                            eventFields
                            (Just signatoryLink)
                            Nothing
                        $ actor

                    -- Updating phone number - mobile workflow only and only if not provided
                    forM_ phoneNumber $ \phone -> do
                      let
                        formattedPhoneFromEIDService = "+47" <> phone
                        slPhoneNumber                = getMobile signatoryLink
                        signatoryLinkIsEmpty         = slPhoneNumber == ""
                        formattedPhoneFromSignatory =
                          T.filter (\c -> c `notElem` (" -" :: String)) slPhoneNumber
                      when
                          (  not signatoryLinkIsEmpty
                          && formattedPhoneFromSignatory
                          /= formattedPhoneFromEIDService
                          )
                        $ do
                            logAttention_
                              "Not matching phone for NO BankID - should be blocked by EID provider"
                            internalError
                      when (signatoryLinkIsEmpty && Pending == documentstatus doc) $ do
                        dbUpdate $ UpdatePhoneAfterIdentificationToView
                          signatoryLink
                          phone
                          formattedPhoneFromEIDService
                          actor

                    chargeForItemSingle CINOBankIDAuthentication $ documentid doc
                  return EIDServiceTransactionStatusCompleteAndSuccess
        (EIDServiceTransactionStatusCompleteAndSuccess, Nothing) -> do
          mergeEIDServiceTransactionWithStatus
            EIDServiceTransactionStatusCompleteAndFailed
          return EIDServiceTransactionStatusCompleteAndFailed
        _ -> do
          mergeEIDServiceTransactionWithStatus ts
          return ts
  where
    mergeEIDServiceTransactionWithStatus newstatus =
      dbUpdate . MergeEIDServiceTransaction $ est { estStatus = newstatus }
    decodeCertificate :: Text -> BSC8.ByteString
    decodeCertificate =
      either (unexpectedError "invalid base64 of NOBankID certificate") identity
        . B64.decode
        . T.encodeUtf8
    flashErrWithMessage :: Kontrakcja m => String -> m ()
    flashErrWithMessage = addFlashCookie . toCookieValue . toFlashMsg OperationFailed
    resolveDateOfBirthFromSSN :: Text -> Text
    resolveDateOfBirthFromSSN personalnumber =
      case T.chunksOf 2 (T.take 6 personalnumber) of
        [day, month, year] ->
          let yearWithoutCentury = read year
              sequenceNumber = read . T.take 3 . T.drop 6 $ personalnumber
              century = showt $ resolveCentury yearWithoutCentury sequenceNumber
          in  century <> year <> "-" <> month <> "-" <> day
        _ ->
          unexpectedError
            $  "This personal number cannot be formatted to date: "
            <> personalnumber
      where
        resolveCentury :: Int -> Int -> Int
        resolveCentury yearWithoutCentury sequenceNumber
          | yearWithoutCentury > 53 && sequenceNumber > 500 && sequenceNumber < 750 = 18
          | yearWithoutCentury > 40 && sequenceNumber > 899 = 19
          | yearWithoutCentury < 40 && sequenceNumber > 499 = 20
          | otherwise = 19
