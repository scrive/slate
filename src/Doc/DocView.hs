{-# LANGUAGE ExtendedDefaultRules #-}
module Doc.DocView (
    pageCreateFromTemplate
  , documentAuthorInfo
  , documentInfoFields
  , flashDocumentSend
  , flashDocumentSignedAndSend
  , flashAuthorSigned
  , flashDocumentDraftSaved
  , flashDocumentRestarted
  , flashDocumentProlonged
  , flashDocumentTemplateSaved
  , flashMessageCSVSent
  , flashMessageInvalidCSV
  , flashRemindMailSent
  , mailDocumentAwaitingForAuthor
  , mailDocumentClosed
  , mailDocumentRejected
  , mailDocumentRemind
  , mailInvitation
  , modalRejectedView
  , pageDocumentDesign
  , pageDocumentView
  , pageDocumentSignView
  , documentJSON
  , gtVerificationPage
  ) where

import AppView (kontrakcja, standardPageFields)
import Company.Model
import Doc.DocProcess
import Doc.DocStateData
import Doc.DocUtils
import Doc.DocViewMail
import qualified Doc.EvidenceAttachments as EvidenceAttachments
import FlashMessage
import Kontra
import KontraLink
import MinutesTime
import Utils.Prelude
import Utils.Monoid
import Text.StringTemplates.Templates
import Util.HasSomeCompanyInfo
import Util.HasSomeUserInfo
import Util.SignatoryLinkUtils
import User.Model
import Doc.JSON()
import Doc.DocInfo
import Control.Applicative ((<$>))
import Control.Monad.Reader
import qualified Data.ByteString.Char8 as BSC
import Data.Maybe
import Text.JSON
import Data.List (sortBy, nub)
import File.Model
import DB
import PadQueue.Model
import Text.JSON.Gen hiding (value)
import qualified Text.JSON.Gen as J
import qualified Text.StringTemplates.Fields as F
import qualified Data.Set as Set
import Analytics.Include

pageCreateFromTemplate :: TemplatesMonad m => m String
pageCreateFromTemplate = renderTemplate_ "createFromTemplatePage"

modalRejectedView :: TemplatesMonad m => Document -> m FlashMessage
modalRejectedView document = do
  let activatedSignatories = [sl | sl <- documentsignatorylinks document
                                 , isActivatedSignatory (documentcurrentsignorder document) sl || isAuthor sl]
  partylist <- renderListTemplate . map getSmartName $ partyList (document { documentsignatorylinks = activatedSignatories })
  toModal <$> (renderTemplate "modalRejectedView" $ do
    F.value "partyList" partylist
    F.value "documenttitle" $ documenttitle document)


flashDocumentSend :: TemplatesMonad m => m FlashMessage
flashDocumentSend =
  toFlashMsg SigningRelated <$> renderTemplate_ "flashDocumentSend"

flashDocumentSignedAndSend :: TemplatesMonad m => m FlashMessage
flashDocumentSignedAndSend =
  toFlashMsg SigningRelated <$> renderTemplate_ "flashDocumentSignedAndSend"

flashDocumentDraftSaved :: TemplatesMonad m => m FlashMessage
flashDocumentDraftSaved =
  toFlashMsg SigningRelated <$> renderTemplate_ "flashDocumentDraftSaved"


flashDocumentTemplateSaved :: TemplatesMonad m => m FlashMessage
flashDocumentTemplateSaved =
  toFlashMsg SigningRelated <$> renderTemplate_ "flashDocumentTemplateSaved"

flashDocumentRestarted :: TemplatesMonad m => Document -> m FlashMessage
flashDocumentRestarted document = do
  toFlashMsg OperationDone <$> (renderTemplateForProcess document processflashmessagerestarted $ documentInfoFields document)

flashDocumentProlonged :: TemplatesMonad m => Document -> m FlashMessage
flashDocumentProlonged document = do
  toFlashMsg OperationDone <$> (renderTemplateForProcess document processflashmessageprolonged $ documentInfoFields document)

flashRemindMailSent :: TemplatesMonad m => SignatoryLink -> m FlashMessage
flashRemindMailSent signlink@SignatoryLink{maybesigninfo} =
  toFlashMsg OperationDone <$> (renderTemplate (template_name maybesigninfo) $ do
    F.value "personname" $ getSmartName signlink)
  where
    template_name =
      maybe "flashRemindMailSentNotSigned"
      (const "flashRemindMailSentSigned")

flashAuthorSigned :: TemplatesMonad m => m FlashMessage
flashAuthorSigned =
  toFlashMsg OperationDone <$> renderTemplate_ "flashAuthorSigned"

flashMessageInvalidCSV :: TemplatesMonad m => m FlashMessage
flashMessageInvalidCSV =
  toFlashMsg OperationFailed <$> renderTemplate_ "flashMessageInvalidCSV"

flashMessageCSVSent :: TemplatesMonad m => Int -> m FlashMessage
flashMessageCSVSent doccount =
  toFlashMsg OperationDone <$> (renderTemplate "flashMessageCSVSent" $ F.value "doccount" doccount)

documentJSON :: (TemplatesMonad m, KontraMonad m, MonadDB m, MonadIO m) => Bool -> Bool -> Bool -> PadQueue -> Maybe SignatoryLink -> Document -> m JSValue
documentJSON includeEvidenceAttachments forapi forauthor pq msl doc = do
    ctx <- getContext
    file <- documentfileM doc
    sealedfile <- documentsealedfileM doc
    authorattachmentfiles <- mapM (dbQuery . GetFileByFileID . authorattachmentfile) (documentauthorattachments doc)
    evidenceattachments <- if includeEvidenceAttachments then EvidenceAttachments.fetch doc else return []
    let isauthoradmin = maybe False (flip isAuthorAdmin doc) (ctxmaybeuser ctx)
    mauthor <- maybe (return Nothing) (dbQuery . GetUserByID) (getAuthorSigLink doc >>= maybesignatory)
    mcompany <- maybe (return Nothing) (dbQuery . GetCompanyByUserID) (getAuthorSigLink doc >>= maybesignatory)
    runJSONGenT $ do
      J.value "id" $ show $ documentid doc
      J.value "title" $ documenttitle doc
      J.value "file" $ fmap fileJSON file
      J.value "sealedfile" $ fmap fileJSON sealedfile
      J.value "authorattachments" $ map fileJSON (catMaybes authorattachmentfiles)
      J.objects "evidenceattachments" $ for evidenceattachments $ \a -> do
        J.value "name"     $ BSC.unpack $ EvidenceAttachments.name a
        J.value "mimetype" $ BSC.unpack <$> EvidenceAttachments.mimetype a
        J.value "downloadLink" $ show $ LinkEvidenceAttachment (documentid doc) (EvidenceAttachments.name a)
      J.value "timeouttime" $ jsonDate $ unTimeoutTime <$> documenttimeouttime doc
      J.value "status" $ show $ documentstatus doc
      J.objects "signatories" $ map (signatoryJSON forapi forauthor pq doc msl) (documentsignatorylinks doc)
      J.value "signorder" $ unSignOrder $ documentcurrentsignorder doc
      J.value "authentication" $ case nub (map signatorylinkauthenticationmethod (documentsignatorylinks doc)) of
                                   [StandardAuthentication] -> "standard"
                                   [ELegAuthentication]     -> "eleg"
                                   _                        -> "mixed"
      J.value "delivery" $ deliveryJSON $ documentdeliverymethod doc
      J.value "template" $ isTemplate doc
      J.value "daystosign" $ documentdaystosign doc
      J.value "invitationmessage" $ documentinvitetext doc
      J.value "lang" $  case (getLang doc) of
                             LANG_EN -> "gb"
                             LANG_SV -> "sv"
      J.objects "tags" $ for (Set.toList $ documenttags doc) $ \(DocumentTag n v) -> do
                                    J.value "name"  n
                                    J.value "value" v
      J.value "apicallbackurl" $ documentapicallbackurl doc
      when (not $ forapi) $ do
        J.value "signviewlogo" $ if ((isJust $ companysignviewlogo . companyui =<<  mcompany))
                                    then Just (show (LinkCompanySignViewLogo $ companyid $ fromJust mcompany))
                                    else Nothing
        J.value "signviewtextcolour" $ companysignviewtextcolour . companyui =<< mcompany
        J.value "signviewtextfont" $ companysignviewtextfont . companyui =<< mcompany
        J.value "signviewbarscolour" $ companysignviewbarscolour . companyui =<<  mcompany
        J.value "signviewbarstextcolour" $ companysignviewbarstextcolour . companyui  =<< mcompany
        J.value "signviewbackgroundcolour" $ companysignviewbackgroundcolour . companyui  =<< mcompany
        J.value "author" $ authorJSON mauthor mcompany
        J.value "process" $ show $ toDocumentProcess (documenttype doc)
        J.value "canberestarted" $ isAuthor msl && ((documentstatus doc) `elem` [Canceled, Timedout, Rejected])
        J.value "canbeprolonged" $ isAuthor msl && ((documentstatus doc) `elem` [Timedout])
        J.value "canbecanceled" $ (isAuthor msl || isauthoradmin) && documentstatus doc == Pending
        J.value "canseeallattachments" $ isAuthor msl || isauthoradmin

authenticationJSON :: AuthenticationMethod -> JSValue
authenticationJSON StandardAuthentication = toJSValue "standard"
authenticationJSON ELegAuthentication     = toJSValue "eleg"

deliveryJSON :: DeliveryMethod -> JSValue
deliveryJSON EmailDelivery = toJSValue "email"
deliveryJSON PadDelivery = toJSValue "pad"
deliveryJSON APIDelivery = toJSValue "api"

signatoryJSON :: (TemplatesMonad m, MonadDB m) => Bool -> Bool -> PadQueue -> Document -> Maybe SignatoryLink -> SignatoryLink -> JSONGenT m ()
signatoryJSON forapi forauthor pq doc viewer siglink = do
    J.value "id" $ show $ signatorylinkid siglink
    J.value "current" $ isCurrent
    J.value "signorder" $ unSignOrder $ signatorysignorder $ signatorydetails siglink
    J.value "undeliveredEmail" $ invitationdeliverystatus siglink == Undelivered
    J.value "deliveredEmail" $ invitationdeliverystatus siglink == Delivered
    J.value "signs" $ isSignatory siglink
    J.value "author" $ isAuthor siglink
    J.value "saved" $ isJust . maybesignatory $ siglink
    J.value "datamismatch" $ signatorylinkelegdatamismatchmessage siglink
    J.value "signdate" $ jsonDate $ signtime <$> maybesigninfo siglink
    J.value "seendate" $ jsonDate $ signtime <$> maybeseeninfo siglink
    J.value "readdate" $ jsonDate $ maybereadinvite siglink
    J.value "rejecteddate" $ jsonDate rejectedDate
    J.value "fields" $ signatoryFieldsJSON doc siglink
    J.value "status" $ show $ signatorylinkstatusclass siglink
    J.objects "attachments" $ map signatoryAttachmentJSON (signatoryattachments siglink)
    J.value "csv" $ csvcontents <$> signatorylinkcsvupload siglink
    J.value "inpadqueue"  $ (fmap fst pq == Just (documentid doc)) && (fmap snd pq == Just (signatorylinkid siglink))
    J.value "hasUser" $ isJust (maybesignatory siglink) && isCurrent -- we only inform about current user
    J.value "signsuccessredirect" $ signatorylinksignredirecturl siglink
    J.value "authentication" $ authenticationJSON $ signatorylinkauthenticationmethod siglink
    when (not (isPreparation doc) && forauthor && forapi && documentdeliverymethod doc == APIDelivery) $ do
        J.value "signlink" $ show $ LinkSignDoc doc siglink
    where
      isCurrent = (signatorylinkid <$> viewer) == (Just $ signatorylinkid siglink)
      rejectedDate = signatorylinkrejectiontime siglink

signatoryAttachmentJSON :: MonadDB m => SignatoryAttachment -> JSONGenT m ()
signatoryAttachmentJSON sa = do
  mfile <- lift $ case (signatoryattachmentfile sa) of
    Just fid -> dbQuery $ GetFileByFileID fid
    _ -> return Nothing
  J.value "name" $ signatoryattachmentname sa
  J.value "description" $ signatoryattachmentdescription sa
  J.value "file" $ fileJSON <$> mfile

signatoryFieldsJSON :: Document -> SignatoryLink -> JSValue
signatoryFieldsJSON doc sl@(SignatoryLink{signatorydetails = SignatoryDetails{signatoryfields}}) = JSArray $
  for orderedFields $ \sf@SignatoryField{sfType, sfValue, sfPlacements, sfObligatory} -> do

    case sfType of
      FirstNameFT           -> fieldJSON "standard" "fstname"   sfValue
                                  ((not $ null $ sfValue)  && (not $ isPreparation doc))
                                  sfObligatory sfPlacements
      LastNameFT            -> fieldJSON "standard" "sndname"   sfValue
                                  ((not $ null $ sfValue)  && (not $ isPreparation doc))
                                  sfObligatory sfPlacements
      EmailFT               -> fieldJSON "standard" "email"     sfValue
                                  ((not $ null $ sfValue)  && (not $ isPreparation doc))
                                  sfObligatory sfPlacements
      PersonalNumberFT      -> fieldJSON "standard" "sigpersnr" sfValue
                                  ((not $ null $ sfValue)  && (not $ isPreparation doc))
                                  sfObligatory sfPlacements
      CompanyFT             -> fieldJSON "standard" "sigco"     sfValue
                                  ((not $ null $ sfValue)  && (null sfPlacements) &&
                                      (ELegAuthentication /= signatorylinkauthenticationmethod sl) &&
                                      (not $ isPreparation doc))
                                  sfObligatory sfPlacements
      CompanyNumberFT       -> fieldJSON "standard" "sigcompnr"  sfValue
                                  (closedF sf && (not $ isPreparation doc))
                                  sfObligatory sfPlacements
      SignatureFT label     -> fieldJSON "signature" label sfValue
                                  (closedSignatureF sf && (not $ isPreparation doc))
                                  sfObligatory sfPlacements
      CustomFT label closed -> fieldJSON "custom" label          sfValue
                                  (closed  && (not $ isPreparation doc))
                                  sfObligatory sfPlacements
      CheckboxFT label      -> fieldJSON "checkbox" label sfValue
                                  False
                                  sfObligatory sfPlacements
  where
    closedF sf = ((not $ null $ sfValue sf) || (null $ sfPlacements sf))
    closedSignatureF sf = ((not $ null $ dropWhile (/= ',') $ sfValue sf) && (null $ sfPlacements sf) && ((PadDelivery /= documentdeliverymethod doc)))
    orderedFields = sortBy (\f1 f2 -> ftOrder (sfType f1) (sfType f2)) signatoryfields
    ftOrder FirstNameFT _ = LT
    ftOrder LastNameFT _ = LT
    ftOrder EmailFT _ = LT
    ftOrder CompanyFT _ = LT
    ftOrder PersonalNumberFT _ = LT
    ftOrder CompanyNumberFT _ = LT
    ftOrder _ _ = EQ

fieldJSON :: String -> String -> String -> Bool -> Bool -> [FieldPlacement] -> JSValue
fieldJSON tp name value closed obligatory placements = runJSONGen $ do
    J.value "type" tp
    J.value "name" name
    J.value "value" value
    J.value "closed" closed
    J.value "obligatory" obligatory
    J.value "placements" $ map placementJSON placements


placementJSON :: FieldPlacement -> JSValue
placementJSON placement = runJSONGen $ do
    J.value "xrel" $ placementxrel placement
    J.value "yrel" $ placementyrel placement
    J.value "wrel" $ placementwrel placement
    J.value "hrel" $ placementhrel placement
    J.value "fsrel" $ placementfsrel placement
    J.value "page" $ placementpage placement
    J.value "tip" $ case (placementtipside placement) of
                         Just LeftTip -> Just "left"
                         Just RightTip -> Just "right"
                         _ -> Nothing

jsonDate :: Maybe MinutesTime -> JSValue
jsonDate mdate = toJSValue $ formatMinutesTimeRealISO <$> mdate

fileJSON :: File -> JSValue
fileJSON file = runJSONGen $ do
    J.value "id" $ show $ fileid file
    J.value "name" $ filename file

authorJSON :: Maybe User -> Maybe Company -> JSValue
authorJSON mauthor mcompany = runJSONGen $ do
    J.value "fullname" $ getFullName <$> mauthor
    J.value "email" $ getEmail <$> mauthor
    J.value "company" $ (\a -> getCompanyName (a,mcompany)) <$> mauthor
    J.value "phone" $ userphone <$> userinfo <$> mauthor
    J.value "position" $ usercompanyposition <$> userinfo <$>mauthor



pageDocumentDesign :: TemplatesMonad m
                   => Document
                   -> m String
pageDocumentDesign document = do
     renderTemplate "pageDocumentDesign" $ do
         F.value "documentid" $ show $ documentid document

pageDocumentView :: TemplatesMonad m
                    => Document
                    -> Maybe SignatoryLink
                    -> Bool
                    -> m String
pageDocumentView document msiglink authorcompanyadmin =
  renderTemplate "pageDocumentView" $ do
      F.value "documentid" $ show $ documentid document
      F.value "siglinkid" $ fmap (show . signatorylinkid) msiglink
      F.value "authorcompanyadmin" $ authorcompanyadmin


pageDocumentSignView :: TemplatesMonad m
                    => Context
                    -> Document
                    -> SignatoryLink
                    -> AnalyticsData
                    -> m String
pageDocumentSignView ctx document siglink ad =
  renderTemplate "pageDocumentSignView" $ do
      F.value "documentid" $ show $ documentid document
      F.value "siglinkid" $ show $ signatorylinkid siglink
      F.value "documenttitle" $ documenttitle document
      F.value "usestandardheaders" $ (isJust $ maybesignatory siglink) && (maybesignatory siglink) == (userid <$> ctxmaybeuser ctx)
      standardPageFields ctx kontrakcja ad


-- | Basic info about document , name, id ,author
documentInfoFields :: Monad m => Document -> Fields m ()
documentInfoFields  document  = do
  F.value "documenttitle" $ documenttitle document
  F.value "title" $ documenttitle document
  F.value "name" $ documenttitle document
  F.value "id" $ show $ documentid document
  F.value "documentid" $ show $ documentid document
  F.value "template" $  isTemplate document
  -- F.value "emailauthenticationselected" $ document `allowsAuthMethod` StandardAuthentication
  -- F.value "elegauthenticationselected" $ document `allowsAuthMethod` ELegAuthentication
  F.value "emaildeliveryselected" $ documentdeliverymethod document == EmailDelivery
  F.value "paddeliveryselected" $ documentdeliverymethod document == PadDelivery
  F.value "hasanyattachments" $ length (documentauthorattachments document) + length (concatMap signatoryattachments $ documentsignatorylinks document) > 0
  documentStatusFields document

documentAuthorInfo :: Monad m => Document -> Fields m ()
documentAuthorInfo document =
  case getAuthorSigLink document of
    Nothing -> return ()
    Just siglink -> do
      F.value "authorfstname"       $ nothingIfEmpty $ getFirstName      siglink
      F.value "authorsndname"       $ nothingIfEmpty $ getLastName       siglink
      F.value "authorcompany"       $ nothingIfEmpty $ getCompanyName    siglink
      F.value "authoremail"         $ nothingIfEmpty $ getEmail          siglink
      F.value "authorpersonnumber"  $ nothingIfEmpty $ getPersonalNumber siglink
      F.value "authorcompanynumber" $ nothingIfEmpty $ getCompanyNumber  siglink

-- | Fields indication what is a document status
documentStatusFields :: Monad m => Document -> Fields m ()
documentStatusFields document = do
  F.value "preparation" $ documentstatus document == Preparation
  F.value "pending" $ documentstatus document == Pending
  F.value "cancel" $ (documentstatus document == Canceled
      && (all (not . isJust . signatorylinkelegdatamismatchmessage) $ documentsignatorylinks document))
  F.value "timedout" $ documentstatus document == Timedout
  F.value "rejected" $ documentstatus document == Rejected
  F.value "signed" $ documentstatus document == Closed
  -- awaitingauthor is used in old view in old template
  -- remove it when old view is removed
  -- currently it means: is the next turn for author to sign?
  F.value "awaitingauthor" $ canAuthorSignNow document
  F.value "datamismatch" $ (documentstatus document == Canceled
      && (any (isJust . signatorylinkelegdatamismatchmessage) $ documentsignatorylinks document))

-- Page for GT verification
gtVerificationPage :: TemplatesMonad m => m String
gtVerificationPage = renderTemplate_ "gtVerificationPage"
