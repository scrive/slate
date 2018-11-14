{-# LANGUAGE ExtendedDefaultRules #-}
{- |
   DocControl represents the controler (in MVC) of the document.
 -}
module Doc.DocControl(
    -- Exported utils or test functions
      sendReminderEmail
    -- Top level handlers
    , handleNewDocument
    , showCreateFromTemplate
    , handleDownloadClosedFile
    , handleSignShow
    , handleSignShowSaveMagicHash
    , handleSignFromTemplate
    , handleEvidenceAttachment
    , handleIssueShowGet
    , handleIssueGoToSignview
    , handleIssueGoToSignviewPad
    , prepareEmailPreview
    , handleResend
    , showPage
    , showPreview
    , showPreviewForSignatory
    , handleFilePages
    , handleShowVerificationPage
    , handleVerify
    , handleMarkAsSaved
    , handleAfterSigning
    , handlePadList
    , handleToStart
    , handleToStartShow
) where

import Control.Conditional (unlessM, whenM)
import Control.Monad.Base
import Control.Monad.Catch
import Control.Monad.Reader
import Data.String.Utils (replace, strip)
import Happstack.Server hiding (lookCookieValue, simpleHTTP, timeout)
import Log
import System.Directory
import System.IO.Temp
import Text.JSON hiding (Result)
import Text.StringTemplates.Templates
import qualified Control.Exception.Lifted as E
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as BSL
import qualified Data.Text as T
import qualified Data.Traversable as T
import qualified Text.JSON.Gen as J

import Analytics.Include
import AppView
import Attachment.AttachmentID (AttachmentID)
import Attachment.Model
import Chargeable.Model
import Cookies
import DB
import DB.TimeZoneName
import Doc.API.Callback.Model
import Doc.Conditions
import Doc.DocInfo
import Doc.DocMails
import Doc.DocStateData
import Doc.DocStateQuery
import Doc.DocumentID
import Doc.DocumentMonad (DocumentMonad, theDocument, withDocument, withDocumentID, withDocumentM)
import Doc.DocUtils (fileFromMainFile)
import Doc.DocView
import Doc.DocViewMail
import Doc.Logging
import Doc.Model
import Doc.SignatoryFieldID
import Doc.SignatoryLinkID
import Doc.Tokens.Model
import EvidenceLog.Model (CurrentEvidenceEventType(..), InsertEvidenceEventWithAffectedSignatoryAndMsg(..))
import FeatureFlags.Model
import File.File (fileid)
import File.Model
import File.Storage (getFileIDContents)
import Happstack.Fields
import InternalResponse
import Kontra
import KontraLink
import Log.Identifier
import MagicHash
import Redirect
import User.Email
import User.Model
import User.Utils
import UserGroup.Model (UserGroupGet(..))
import UserGroup.Types.Subscription
import Util.Actor
import Util.HasSomeUserInfo
import Util.MonadUtils
import Util.PDFUtil
import Util.SignatoryLinkUtils
import qualified Doc.EvidenceAttachments as EvidenceAttachments
import qualified GuardTime as GuardTime

handleNewDocument :: Kontrakcja m => m InternalKontraResponse
handleNewDocument = withUser $ \user -> do
  ctx <- getContext
  title <- renderTemplate_ "newDocumentTitle"
  actor <- guardJustM $ mkAuthorActor <$> getContext
  mtimezonename <- (lookCookieValue "timezone" . rqHeaders) <$> askRq
  case mtimezonename of
    Nothing -> logInfo_ "'timezone' cookie not found"
    _ -> return ()
  timezone <- fromMaybe defaultTimeZoneName <$> T.sequence (mkTimeZoneName <$> mtimezonename)
  timestamp <- formatTimeSimpleWithTZ timezone (get ctxtime ctx)
  doc <- dbUpdate $ NewDocument user (replace "  " " " $ title ++ " " ++ timestamp) Signable timezone 1 actor
  -- Default document on the frontend has different requirements,
  -- this sets up the signatories to match those requirements.
  (authToView, authToSign, invitationDelivery, confirmationDelivery) <- do
    ug <- guardJustM . dbQuery $ UserGroupGet (usergroupid user)
    features <- ugSubFeatures <$> getSubscription ug
    let ff = if useriscompanyadmin user
                then fAdminUsers features
                else fRegularUsers features
    return ( firstAllowedAuthenticationToView ff
           , firstAllowedAuthenticationToSign ff
           , firstAllowedInvitationDelivery ff
           , firstAllowedConfirmationDelivery ff)
  withDocument doc $ do
      authorsiglink <- guardJust $ find (\sl -> signatoryisauthor sl) (documentsignatorylinks doc)
      othersiglink  <- guardJust $ find (\sl -> not $ signatoryisauthor sl)  (documentsignatorylinks doc)
      let fields  = [
              SignatoryNameField $ NameField {
                  snfID                     = (unsafeSignatoryFieldID 0)
                , snfNameOrder              = NameOrder 1
                , snfValue                  = ""
                , snfObligatory             = False
                , snfShouldBeFilledBySender = False
                , snfPlacements             = []
              }
            , SignatoryNameField $ NameField {
                  snfID                     = (unsafeSignatoryFieldID 0)
                , snfNameOrder              = NameOrder 2
                , snfValue                  = ""
                , snfObligatory             = False
                , snfShouldBeFilledBySender = False
                , snfPlacements             = []
              }
            , SignatoryEmailField $ EmailField {
                  sefID                     = (unsafeSignatoryFieldID 0)
                , sefValue                  = ""
                , sefObligatory             = True
                , sefShouldBeFilledBySender = False
                , sefEditableBySignatory    = False
                , sefPlacements             = []
              }
            , SignatoryMobileField $ MobileField {
                  smfID                     = (unsafeSignatoryFieldID 0)
                , smfValue                  = ""
                , smfObligatory             = False
                , smfShouldBeFilledBySender = False
                , smfEditableBySignatory    = False
                , smfPlacements             = []
              }
            , SignatoryCompanyField $ CompanyField {
                  scfID                     = (unsafeSignatoryFieldID 0)
                , scfValue                  = ""
                , scfObligatory             = False
                , scfShouldBeFilledBySender = False
                , scfPlacements             = []
              }
            ]
          authorsiglink' = authorsiglink
            { signatorylinkdeliverymethod = invitationDelivery
            , signatorylinkconfirmationdeliverymethod = confirmationDelivery
            , signatorylinkauthenticationtoviewmethod = authToView
            , signatorylinkauthenticationtosignmethod = authToSign
            }
          othersiglink' = othersiglink
            { signatorysignorder = SignOrder 1
            , signatoryfields = fields
            , signatorylinkdeliverymethod = invitationDelivery
            , signatorylinkconfirmationdeliverymethod = confirmationDelivery
            , signatorylinkauthenticationtoviewmethod = authToView
            , signatorylinkauthenticationtosignmethod = authToSign
            }
      void $ dbUpdate $ ResetSignatoryDetails [authorsiglink', othersiglink'] actor
      dbUpdate $ SetDocumentUnsavedDraft True
      logInfo "New document created" $ logObject_ doc
      return $ internalResponse $ LinkIssueDoc (documentid doc)

{-
  Document state transitions are described in DocState.

  Here are all actions associated with transitions.
-}

formatTimeSimpleWithTZ :: (MonadDB m, MonadThrow m) => TimeZoneName -> UTCTime -> m String
formatTimeSimpleWithTZ tz t = do
  runQuery_ $ rawSQL "SELECT to_char($1 AT TIME ZONE $2, 'YYYY-MM-DD HH24:MI')" (t, tz)
  fetchOne runIdentity

showCreateFromTemplate :: Kontrakcja m => m InternalKontraResponse
showCreateFromTemplate = withUser $ \_ -> do
  internalResponse <$> (pageCreateFromTemplate =<< getContext)

{- |
    Call after signing in order to save the document for any user, and
    put up the appropriate modal.
-}
handleAfterSigning :: (MonadLog m, MonadThrow m, TemplatesMonad m, DocumentMonad m, MonadBase IO m) => SignatoryLinkID -> m ()
handleAfterSigning slid = logSignatory slid $ do
  signatorylink <- guardJust . getSigLinkFor slid =<< theDocument
  maybeuser <- dbQuery $ GetUserByEmail (Email $ getEmail signatorylink)
  case maybeuser of
    Just user | isJust $ userhasacceptedtermsofservice user-> do
      void $ dbUpdate $ SaveDocumentForUser user slid
      return ()
    _ -> return ()


-- |
-- Show the document to be signed.
--
-- We put links of the form:
--
--   /s/[documentid]/[signatorylinkid]/[magichash]
--
-- in emails. The magichash should be stored in session, redirect
-- should happen immediatelly, every following action should use
-- magichash stored.
--
-- Note: JavaScript should never be allowed to see magichash in any
-- form. Therefore we do immediate redirect without any content.
--
-- Warning: iPhones have this problem: they randomly disable cookies
-- in Safari so cookies cannot be stored. This breaks all session
-- related machinery. Everybody is suffering from this. For now we
-- handle this as special case, but this is not secure and should just
-- be removed. To iPhone users with disabled cookies: tell them to
-- call Apple service and enable cookies (again) on their phone.
{-# NOINLINE handleSignShowSaveMagicHash #-}
handleSignShowSaveMagicHash :: Kontrakcja m => DocumentID -> SignatoryLinkID -> MagicHash -> m Response
handleSignShowSaveMagicHash did sid mh = logDocumentAndSignatory did sid $
  (do
    dbQuery (GetDocumentByDocumentIDSignatoryLinkIDMagicHash did sid mh) `withDocumentM` do
      guardThatDocumentIsReadableBySignatories =<< theDocument
      dbUpdate $ AddDocumentSessionToken sid mh
      -- Redirect to propper page
      sendRedirect $ LinkSignDocNoMagicHash did sid
  )
  `catchDBExtraException` (\(DocumentDoesNotExist _) -> respond404)
  `catchDBExtraException` (\SignatoryTokenDoesNotMatch -> respondLinkInvalid)
  `catchDBExtraException` (\(_ :: DocumentWasPurged) -> respondLinkInvalid)

handleSignFromTemplate :: Kontrakcja m => DocumentID -> MagicHash -> m Response
handleSignFromTemplate tplID mh = logDocument tplID $ do
  ctx <- getContext
  tpl <- dbQuery $ GetDocumentByDocumentIDAndShareableLinkHash tplID mh

  let actor = systemActor $ get ctxtime ctx
  mDocID <- withDocument tpl $
    dbUpdate $ CloneDocumentWithUpdatedAuthor Nothing tpl actor $ \doc ->
      doc { documenttype = Signable }

  case mDocID of
    Nothing -> do
      logAttention "Cloning shareable template failed" $ object [identifier tplID]
      respondLinkInvalid

    Just docID -> withDocumentID docID $ do
      timezone <- documenttimezonename <$> theDocument
      dbUpdate $ PreparationToPending actor timezone
      mSL <- (find (not . isAuthor) . documentsignatorylinks) <$> theDocument

      case mSL of
        Nothing -> do
          logAttention "Can't find suitable signatory for shareable\
                       \ template" $ object [identifier docID]
          respondLinkInvalid
        Just sl -> do
          dbUpdate $ ChargeUserGroupForShareableLink docID
          dbUpdate $ AddDocumentSessionToken (signatorylinkid sl)
                                             (signatorymagichash sl)
          sendRedirect $ LinkSignDocNoMagicHash docID $ signatorylinkid sl

-- |
--   /s/[documentid]/[signatorylinkid] and /sp/[documentid]/[signatorylinkid]

{-# NOINLINE handleSignShow #-}
handleSignShow :: Kontrakcja m => DocumentID -> SignatoryLinkID -> m Response
handleSignShow did slid = logDocumentAndSignatory did slid $ do
  mmagichash <- dbQuery $ GetDocumentSessionToken slid
  case mmagichash of
    Just magichash -> do
      doc <- dbQuery $ GetDocumentByDocumentIDSignatoryLinkIDMagicHash did slid magichash
      invitedlink <- guardJust $ getSigLinkFor slid doc
      -- We always switch to document langauge in case of pad signing
      switchLang $ getLang doc
      ctx <- getContext -- Order is important since ctx after switchLang changes
      ad <- getAnalyticsData
      needsToIdentify <- signatoryNeedsToIdentifyToView invitedlink doc
      if needsToIdentify
        then doc `withDocument` do
          addEventForVisitingSigningPageIfNeeded VisitedViewForAuthenticationEvidence invitedlink
          content <- pageDocumentIdentifyView ctx doc invitedlink ad
          simpleHtmlResponse content
        else do
          if isClosed doc
            then do
              content <- pageDocumentSignView ctx doc invitedlink ad
              simpleHtmlResponse content
            else doc `withDocument` do
              addEventForVisitingSigningPageIfNeeded VisitedViewForSigningEvidence invitedlink
              unlessM ((isTemplate || isPreparation) <$> theDocument) $ do
                dbUpdate . MarkDocumentSeen slid magichash =<< signatoryActor ctx invitedlink
                triggerAPICallbackIfThereIsOne =<< theDocument
              content <- theDocument >>= \d -> pageDocumentSignView ctx d invitedlink ad
              simpleHtmlResponse content
    Nothing -> handleCookieFail slid did

-- |
--   /ts/[documentid] (doc has to be a draft)
{-# NOINLINE handleToStartShow #-}
handleToStartShow :: Kontrakcja m => DocumentID -> m InternalKontraResponse
handleToStartShow documentid = withUserTOS $ \_ -> do
  ctx <- getContext
  document <- getDocByDocIDForAuthor documentid
  ad <- getAnalyticsData
  content <- pageDocumentToStartView ctx document ad
  internalResponse <$> (simpleHtmlResponse content)

-- If is not magic hash in session. It may mean that the
-- session expired and we deleted the credentials already or it
-- may mean that cookies are disabled. Lets try to find out if
-- there are any cookies, if there are none we show a page how
-- to enable cookies on iPhone that seems to be the only
-- offender.
handleCookieFail :: Kontrakcja m => SignatoryLinkID -> DocumentID -> m Response
handleCookieFail slid did = logDocumentAndSignatory did slid $ do
  cookies <- rqCookies <$> askRq
  if null cookies
    then sendRedirect LinkEnableCookies
    else do
      logInfo "Signview load after session timedout" $ object ["cookies" .= show cookies]
      ctx <- getContext
      ad <- getAnalyticsData
      simpleHtmlResponse =<< renderTemplate "sessionTimeOut" (standardPageFields ctx Nothing ad)

{- |
   Redirect author of document to go to signview
   URL: /d/signview/{documentid}
   Method: POST
 -}
handleIssueGoToSignview :: Kontrakcja m => DocumentID -> m InternalKontraResponse
handleIssueGoToSignview docid = withUser $ \user -> do
  doc <- getDocByDocID docid
  case (getMaybeSignatoryLink (doc,user)) of
    Just sl -> do
      dbUpdate $ AddDocumentSessionToken (signatorylinkid sl) (signatorymagichash sl)
      return $ internalResponse $ LinkSignDocNoMagicHash docid (signatorylinkid sl)
    _ -> return $ internalResponse $ LoopBack

{- |
   Redirect author of document to go to signview for any of the pad signatories
   URL: /d/signview/{documentid}/{signatorylinkid}
   Method: POST
 -}
handleIssueGoToSignviewPad :: Kontrakcja m => DocumentID -> SignatoryLinkID
                           -> m KontraLink
handleIssueGoToSignviewPad docid slid= do
  ctx <- getContext
  doc <- getDocByDocIDForAuthor docid
  user <- guardJust $ getContextUser ctx
  case ( isAuthor <$> getMaybeSignatoryLink (doc,user)
       , getMaybeSignatoryLink (doc,slid) ) of
    (Just True,Just sl) | signatorylinkdeliverymethod sl == PadDelivery -> do
      dbUpdate $ AddDocumentSessionToken (signatorylinkid sl)
        (signatorymagichash sl)
      return $ LinkSignDocPad docid slid
    _ -> return LoopBack

handleEvidenceAttachment :: Kontrakcja m => DocumentID -> T.Text -> m InternalKontraResponse
handleEvidenceAttachment docid aname = logDocument docid $ localData ["attachment_name" .= aname] $ withUser $ \_ -> do
  doc <- getDocByDocID docid
  es <- guardJustM $ EvidenceAttachments.extractAttachment doc aname
  return $ internalResponse $ toResponseBS "text/html"  $ es

{- |
   Handles the request to show a document to a logged in user.
   URL: /d/{documentid}
   Method: GET
 -}
handleIssueShowGet :: Kontrakcja m => DocumentID -> m InternalKontraResponse
handleIssueShowGet docid = withUserTOS $ \_ -> do
  document <- getDocByDocID docid
  muser <- get ctxmaybeuser <$> getContext

  authorsiglink <- guardJust $ getAuthorSigLink document

  let ispreparation = documentstatus document == Preparation
      isauthor = (userid <$> muser) == maybesignatory authorsiglink
  mauthoruser <- maybe (return Nothing) (dbQuery . GetUserByIDIncludeDeleted) (maybesignatory authorsiglink)

  let isincompany = isJust muser && ((usergroupid <$> muser) == (usergroupid <$> mauthoruser))
      msiglink = find (isSigLinkFor muser) $ documentsignatorylinks document
  ad <- getAnalyticsData

  ctx <- getContext
  case (ispreparation, msiglink) of
    (True,  _)                       -> do
       -- Never cache design view. IE8 hack. Should be fixed in different wasy
       internalResponse <$> (setHeaderBS "Cache-Control" "no-cache" <$> (simpleHtmlResponse =<< pageDocumentDesign ctx document ad))
    (False, Just sl)
      | isauthor -> if isClosed document
        -- If authenticate to view archived is set for author, we can't show him
        -- the signed document in author's view before he authenticates.
        then signatoryNeedsToIdentifyToView sl document >>= \case
          True  -> fmap internalResponse . simpleHtmlResponse
                     =<< pageDocumentIdentifyView ctx document sl ad
          False -> internalResponse <$> pageDocumentView ctx document msiglink isincompany
        else internalResponse <$> pageDocumentView ctx document msiglink isincompany
      | otherwise -> do
       -- Simply loading pageDocumentSignView doesn't work when signatory needs
       -- to authenticate to view, redirect to proper sign view.
       -- We need link with magic hash for non-author signatories, that
       -- view the document from their archive
       return $ internalResponse $ LinkSignDoc docid sl
    (False, Nothing) | isincompany -> do
      internalResponse <$> pageDocumentView ctx document msiglink isincompany
    _                                -> do
       internalError


{- We return pending message if file is still pending, else we return JSON with number of pages-}
handleFilePages :: Kontrakcja m => FileID -> m Response
handleFilePages fid = logFile fid $ do
  checkFileAccess fid
  ePagesCount <- liftIO . getNumberOfPDFPages =<< getFileIDContents fid
  case ePagesCount of
    Right pc -> simpleJsonResponse . J.runJSONGen . J.value "pages" $ pc
    _ -> do
      logAttention_ "Counting number of pages failed"
      internalError

{- |
   Get some html to display the images of the files
   URL: /pages/{fileid}
   Method: GET
 -}
showPage :: Kontrakcja m => FileID -> Int -> m Response
showPage fid pageNo = logFile fid $ do
  logInfo_ "Checking file access"
  checkFileAccess fid
  pixelwidth <- guardJustM $ readField "pixelwidth"
  let clampedPixelWidth = min 2000 (max 100 pixelwidth)
  fileData <- getFileIDContents fid
  rp <- renderPage fileData pageNo clampedPixelWidth
  case rp of
   Just pageData -> return $ setHeaderBS "Cache-Control" "max-age=604800" $ toResponseBS "image/png" $ BSL.fromStrict pageData
   Nothing -> do
     logAttention "Rendering PDF page failed" $ object [ "page" .= show pageNo]
     internalError

-- | Preview when authorized user is logged in (without magic hash)
showPreview :: Kontrakcja m => DocumentID -> FileID -> m InternalKontraResponse
showPreview did fid = logDocumentAndFile did fid $ withUser $ \_ -> do
  pixelwidth <- fromMaybe 150 <$> readField "pixelwidth"
  let clampedPixelWidth = min 2000 (max 100 pixelwidth)
  void $ getDocByDocID did
  if fid == unsafeFileID 0
    then do
      emptyPreview <- liftIO $ BS.readFile "frontend/app/img/empty-preview.jpg"
      return $ internalResponse $ toResponseBS "image/jpeg" $ BSL.fromStrict emptyPreview
    else do
      checkFileAccessWith fid Nothing Nothing (Just did) Nothing
      internalResponse <$> previewResponse fid clampedPixelWidth

-- | Preview from mail client with magic hash
showPreviewForSignatory :: Kontrakcja m => DocumentID -> SignatoryLinkID -> MagicHash -> FileID -> m Response
showPreviewForSignatory did slid mh fid = logDocumentAndFile did fid $ do
  checkFileAccessWith fid (Just slid) (Just mh) (Just did) Nothing
  pixelwidth <- fromMaybe 150 <$> readField "pixelwidth"
  let clampedPixelWidth = min 2000 (max 100 pixelwidth)
  previewResponse fid clampedPixelWidth

previewResponse :: Kontrakcja m => FileID -> Int -> m Response
previewResponse fid pixelwidth = do
  let clampedPixelWidth = min 2000 (max 100 pixelwidth)
  fileData <- getFileIDContents fid
  rp <- renderPage fileData 1 clampedPixelWidth
  case rp of
   Just pageData -> return $ toResponseBS "image/png" $ BSL.fromStrict pageData
   Nothing -> do
     logAttention_ "Rendering PDF preview failed"
     internalError

handleDownloadClosedFile :: Kontrakcja m => DocumentID -> SignatoryLinkID -> MagicHash -> String -> m Response
handleDownloadClosedFile did sid mh _nameForBrowser = do
  doc <- dbQuery $ GetDocumentByDocumentIDSignatoryLinkIDMagicHash did sid mh
  guardThatDocumentIsReadableBySignatories doc
  if isClosed doc then do
    file <- guardJustM $ fileFromMainFile $ documentsealedfile doc
    content <- getFileIDContents $ fileid file
    return $ respondWithPDF True content
   else respond404

handleResend :: Kontrakcja m => DocumentID -> SignatoryLinkID -> m ()
handleResend docid signlinkid = guardLoggedInOrThrowInternalError $ do
  getDocByDocIDForAuthorOrAuthorsCompanyAdmin docid `withDocumentM` do
    signlink <- guardJust . getSigLinkFor signlinkid =<< theDocument
    customMessage <- fmap strip <$> getField "customtext"
    actor <- guardJustM $ fmap mkAuthorActor getContext
    void $ sendReminderEmail customMessage actor False signlink
    return ()

handlePadList :: Kontrakcja m => m Response
handlePadList = do
  ctx <- getContext
  ad  <- getAnalyticsData
  case getContextUser ctx of
    Just _  -> simpleHtmlResponse =<< pageDocumentPadList ctx  ad
    Nothing -> simpleHtmlResponse =<< pageDocumentPadListLogin ctx  ad

handleToStart :: Kontrakcja m => m Response
handleToStart = do
  ctx <- getContext
  ad  <- getAnalyticsData
  case (get ctxmaybeuser ctx) of
    Just _  -> simpleHtmlResponse =<< pageDocumentToStartList  ctx ad
    Nothing -> simpleHtmlResponse =<< pageDocumentToStartLogin ctx ad

checkFileAccess :: Kontrakcja m => FileID -> m ()
checkFileAccess fid = do

  -- If we have documentid then we look for logged in user and
  -- signatorylinkid and magichash (in cookie). Then we check if file is
  -- reachable as document file, document sealed file, document author
  -- attachment or document signatory attachment.
  --
  -- If we have attachmentid then we look for logged in user and see
  -- if user owns the file or file is shared in user's company.
  --
  -- URLs look like:
  -- /filepages/#fileid/This%20is%file.pdf?documentid=34134124
  -- /filepages/#fileid/This%20is%file.pdf?documentid=34134124&signatorylinkid=412413
  -- /filepages/#fileid/This%20is%file.pdf?attachmentid=34134124
  --
  -- Warning take into account when somebody has saved document into
  -- hers account but we still refer using signatorylinkid.

  msid <- readField "signatory_id"
  mdid <- readField "document_id"
  mattid <- readField "attachment_id"

  -- If refering to something by SignatoryLinkID check out if in the
  -- session we have a properly stored access magic hash.
  mmh <- maybe (return Nothing) (dbQuery . GetDocumentSessionToken) msid
  checkFileAccessWith fid msid mmh mdid mattid

checkFileAccessWith :: Kontrakcja m =>
  FileID -> Maybe SignatoryLinkID -> Maybe MagicHash -> Maybe DocumentID -> Maybe AttachmentID -> m ()
checkFileAccessWith fid msid mmh mdid mattid =
  case (msid, mmh, mdid, mattid) of
    (Just sid, Just mh, Just did,_) -> do
       doc <- dbQuery $ GetDocumentByDocumentIDSignatoryLinkIDMagicHash did sid mh
       guardThatDocumentIsReadableBySignatories doc
       sl <- guardJust $ getSigLinkFor sid doc
       whenM (signatoryNeedsToIdentifyToView sl doc) $ do
         -- If document is not closed, author never needs to identify to
         -- view. However if it's closed, then he might need to.
         when (isClosed doc || not (isAuthor sl)) $ do
           internalError
       indoc <- dbQuery $ FileInDocument did fid
       when (not indoc) $ internalError
    (_,_,Just did,_) -> guardLoggedInOrThrowInternalError $ do
       _doc <- getDocByDocID did
       indoc <- dbQuery $ FileInDocument did fid
       when (not indoc) $ internalError
    (_,_,_,Just attid) -> guardLoggedInOrThrowInternalError $ do
       user <- guardJustM $ get ctxmaybeuser <$> getContext
       atts <- dbQuery $ GetAttachments [ AttachmentsSharedInUsersUserGroup (userid user)
                                            , AttachmentsOfAuthorDeleteValue (userid user) True
                                            , AttachmentsOfAuthorDeleteValue (userid user) False
                                            ]
                                            [ AttachmentFilterByID attid
                                            , AttachmentFilterByFileID fid
                                            ]
                                            []
       when (length atts /= 1) $
                internalError
    _ -> internalError

prepareEmailPreview :: Kontrakcja m => DocumentID -> SignatoryLinkID -> m JSValue
prepareEmailPreview docid slid = do
    mailtype <- getField' "mailtype"
    content <- flip E.catch (\(E.SomeException _) -> return "") $ case mailtype of
         "remind" -> do
             doc <- getDocByDocID docid
             Just sl <- return $ getSigLinkFor slid doc
             mailattachments <- makeMailAttachments doc True
             mailDocumentRemindContent Nothing doc sl (not (null mailattachments))
         "invite" -> do
             doc <- getDocByDocID docid
             mailInvitationContent False Sign Nothing doc
         "confirm" -> do
             doc <- getDocByDocID docid
             mailClosedContent True doc
         _ -> fail "prepareEmailPreview"
    J.runJSONGenT $ J.value "content" content

-- GuardTime verification page. This can't be external since its a page in our system.
-- withAnonymousContext so the verify page looks like the user is not logged in
-- (e.g. for default footer & header)
handleShowVerificationPage :: Kontrakcja m =>  m Response
handleShowVerificationPage = withAnonymousContext gtVerificationPage

handleVerify :: Kontrakcja m => m JSValue
handleVerify = do
      fileinput <- getDataFn' (lookInput "file")
      filepath <- case fileinput of
            Just (Input (Left filepath) _ _) -> return filepath
            Just (Input (Right content) _ _) -> liftIO $ do
                    systmp <- getTemporaryDirectory
                    (pth, fhandle) <- openTempFile systmp "vpath.pdf"
                    BSL.hPutStr fhandle content
                    return pth
            _ -> internalError
      ctx <- getContext
      J.toJSValue <$> GuardTime.verify (get ctxgtconf ctx) filepath

handleMarkAsSaved :: Kontrakcja m => DocumentID -> m JSValue
handleMarkAsSaved docid = guardLoggedInOrThrowInternalError $ do
  getDocByDocID docid `withDocumentM` do
    whenM (isPreparation <$> theDocument) $ dbUpdate $ SetDocumentUnsavedDraft False
    J.runJSONGenT $ return ()

-- Add some event as signatory if this signatory has not signed yet, and document is pending
addEventForVisitingSigningPageIfNeeded :: (Kontrakcja m, DocumentMonad m) => CurrentEvidenceEventType -> SignatoryLink -> m ()
addEventForVisitingSigningPageIfNeeded ev sl = do
  ctx <- getContext
  doc <- theDocument
  when (isPending doc && isSignatoryAndHasNotSigned sl) $ do
    updateMTimeAndObjectVersion $ get ctxtime ctx
    void $ dbUpdate . InsertEvidenceEventWithAffectedSignatoryAndMsg ev  (return ()) (Just sl) Nothing =<< signatoryActor ctx sl

guardThatDocumentIsReadableBySignatories :: Kontrakcja m => Document -> m ()
guardThatDocumentIsReadableBySignatories doc = do
  now <- currentTime
  unless (isAccessibleBySignatories now doc) respondLinkInvalid
