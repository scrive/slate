module Doc.API.V2.Calls.DocumentPostCalls (
  docApiV2New
, docApiV2NewFromTemplate
, docApiV2Update
, docApiV2Start
, docApiV2Prolong
, docApiV2Cancel
, docApiV2Trash
, docApiV2Delete
, docApiV2Remind
, docApiV2Forward
, docApiV2SetFile
, docApiV2SetAttachments
, docApiV2SetAutoReminder
, docApiV2Clone
, docApiV2Restart
, docApiV2SigSetAuthenticationToSign
) where

import Data.Unjson
import Data.Unjson as Unjson
import Happstack.Server.Types
import System.FilePath (dropExtension)
import Text.StringTemplates.Templates
import qualified Data.Text as T

import API.V2
import Attachment.Model
import DB
import DB.TimeZoneName (defaultTimeZoneName)
import Doc.API.Callback.Model (triggerAPICallbackIfThereIsOne)
import Doc.API.V2.DocumentAccess
import Doc.API.V2.DocumentUpdateUtils
import Doc.API.V2.Guards
import Doc.API.V2.JSON.Document
import Doc.API.V2.JSON.Misc
import Doc.API.V2.Parameters
import Doc.Action
import Doc.Anchors
import Doc.AutomaticReminder.Model (setAutoreminder)
import Doc.DocInfo (isPending, isTimedout)
import Doc.DocMails (sendAllReminderEmailsExceptAuthor, sendForwardEmail)
import Doc.DocStateData
import Doc.DocUtils
import Doc.DocumentID
import Doc.DocumentMonad
import Doc.Logging
import Doc.Model
import Doc.SignatoryLinkID
import File.File (File(..))
import File.FileID (FileID)
import InputValidation (Result(..), asValidEmail)
import Kontra
import KontraPrelude
import MinutesTime
import OAuth.Model
import User.Model
import Util.SignatoryLinkUtils (getSigLinkFor, getAuthorSigLink)

docApiV2New :: Kontrakcja m => m Response
docApiV2New = api $ do
  -- Permissions
  (user, actor) <- getAPIUser APIDocCreate
  -- Parameters
  saved <- apiV2ParameterDefault True (ApiV2ParameterBool "saved")
  mFile <- apiV2ParameterOptional (ApiV2ParameterFilePDF "file")
  -- API call actions
  title <- case mFile of
    Nothing -> do
      ctx <- getContext
      title <- renderTemplate_ "newDocumentTitle"
      return $ title ++ " " ++ formatTimeSimple (ctxtime ctx)
    Just f -> return . dropExtension . filename $ f
  (dbUpdate $ NewDocument user title Signable defaultTimeZoneName 0 actor) `withDocumentM` do
    dbUpdate $ SetDocumentUnsavedDraft (not saved)
    case mFile of
      Nothing -> return ()
      Just f -> do
        dbUpdate $ AttachFile (fileid f) actor
  -- Result
    Created <$> (\d -> (unjsonDocument $ documentAccessForUser user d,d)) <$> theDocument


docApiV2NewFromTemplate :: Kontrakcja m => DocumentID -> m Response
docApiV2NewFromTemplate did = logDocument did . api $ do
  -- Permissions
  (user, actor) <- getAPIUser APIDocCreate
  -- Guards
  withDocumentID did $ do
    guardThatUserIsAuthorOrDocumentIsShared user
    guardThatObjectVersionMatchesIfProvided did
    guardThatDocumentIs (isTemplate) "The document is not a template."
    guardThatDocumentIs (not $ flip documentDeletedForUser $ userid user) "The template is in Trash"
  -- API call actions
  template <- dbQuery $ GetDocumentByDocumentID $ did
  (apiGuardJustM (serverError "Can't clone given document") (dbUpdate $ CloneDocumentWithUpdatedAuthor user template actor) >>=) $ flip withDocumentID $ do
    dbUpdate $ DocumentFromTemplate actor
    dbUpdate $ SetDocumentUnsavedDraft False
  -- Result
    Created <$> (\d -> (unjsonDocument $ documentAccessForUser user d,d)) <$> theDocument


docApiV2Update :: Kontrakcja m => DocumentID -> m Response
docApiV2Update did = logDocument did . api $ do
  -- Permissions
  (user, actor) <- getAPIUser APIDocCreate
  withDocumentID did $ do
    -- Guards
    guardThatUserIsAuthor user
    guardThatObjectVersionMatchesIfProvided did
    guardDocumentStatus Preparation
    -- Parameters
    documentJSON <- apiV2ParameterObligatory (ApiV2ParameterAeson "document")
    doc <- theDocument
    let da = documentAccessForUser user doc
    draftData <- case (Unjson.update doc (unjsonDocument da) documentJSON) of
      (Result draftData []) ->
        return draftData
      (Result _ errs) ->
        apiError $ requestParameterParseError "document" $ "Errors while parsing document data:" <+> T.pack (show errs)
    -- API call actions
    applyDraftDataToDocument draftData actor
    -- Result
    Ok <$> (unjsonDocument da,) <$> theDocument


docApiV2Start :: Kontrakcja m => DocumentID -> m Response
docApiV2Start did = logDocument did . api $ do
  -- Permissions
  (user, actor) <- getAPIUser APIDocSend
  withDocumentID did $ do
    -- Guards
    guardThatUserIsAuthor user
    guardThatObjectVersionMatchesIfProvided did
    guardDocumentStatus Preparation
    guardThatDocumentCanBeStarted
    -- Parameters
    authorSignsNow <- apiV2ParameterDefault False (ApiV2ParameterBool "author_signs_now")
    t <- ctxtime <$> getContext
    timezone <- documenttimezonename <$> theDocument
    dbUpdate $ PreparationToPending actor timezone
    dbUpdate $ SetDocumentInviteTime t actor
    postDocumentPreparationChange authorSignsNow timezone
    -- Result
    Ok <$> (\d -> (unjsonDocument $ documentAccessForUser user d,d)) <$> theDocument


docApiV2Prolong :: Kontrakcja m => DocumentID -> m Response
docApiV2Prolong did = logDocument did . api $ do
  -- Permissions
  (user, actor) <- getAPIUser APIDocSend
  withDocumentID did $ do
    -- Guards
    guardThatUserIsAuthorOrCompanyAdmin user
    guardThatObjectVersionMatchesIfProvided did
    guardThatDocumentIs (isTimedout) "The document has not timed out. Only timed out documents can be prolonged."
    -- Parameters
    days <- fromIntegral <$> apiV2ParameterObligatory (ApiV2ParameterInt "days")
    when (days < 1 || days > 90) $
      apiError $ requestParameterInvalid "days" "Days must be a number between 1 and 90"
    -- API call actions
    timezone <- documenttimezonename <$> theDocument
    dbUpdate $ ProlongDocument days timezone actor
    triggerAPICallbackIfThereIsOne =<< theDocument
    -- Result
    Ok <$> (\d -> (unjsonDocument $ documentAccessForUser user d,d)) <$> theDocument


docApiV2Cancel :: Kontrakcja m => DocumentID -> m Response
docApiV2Cancel did = logDocument did . api $ do
  -- Permissions
  (user, actor) <- getAPIUser APIDocSend
  withDocumentID did $ do
    -- Guards
    guardThatUserIsAuthorOrCompanyAdmin user
    guardThatObjectVersionMatchesIfProvided did
    guardDocumentStatus Pending
    -- API call actions
    dbUpdate $ CancelDocument actor
    postDocumentCanceledChange =<< theDocument
    -- Result
    Ok <$> (\d -> (unjsonDocument $ documentAccessForUser user d,d)) <$> theDocument


docApiV2Trash :: Kontrakcja m => DocumentID -> m Response
docApiV2Trash did = logDocument did . api $ do
  -- Permissions
  (user, actor) <- getAPIUser APIDocSend
  withDocumentID did $ do
    -- Guards
    msl <- getSigLinkFor user <$> theDocument
    when (not . isJust $ msl) $ -- This might be a user with an account
      guardThatUserIsAuthorOrCompanyAdmin user
    guardThatObjectVersionMatchesIfProvided did
    guardThatDocumentIs (not . isPending) "Pending documents can not be trashed or deleted"
    -- API call actions
    dbUpdate $ ArchiveDocument (userid user) actor
    -- Result
    Ok <$> (\d -> (unjsonDocument $ documentAccessForUser user d,d)) <$> theDocument


docApiV2Delete :: Kontrakcja m => DocumentID -> m Response
docApiV2Delete did = logDocument did . api $ do
  -- Permissions
  (user, actor) <- getAPIUser APIDocSend
  withDocumentID did $ do
    -- Guards
    msl <- getSigLinkFor user <$> theDocument
    when (not . isJust $ msl) $ -- This might be a user with an account
      guardThatUserIsAuthorOrCompanyAdmin user
    guardThatObjectVersionMatchesIfProvided did
    guardThatDocumentIs (not . isPending) "Pending documents can not be trashed or deleted"
    -- API call actions
    dbUpdate $ ReallyDeleteDocument (userid user) actor
    -- Result
    Ok <$> (\d -> (unjsonDocument $ documentAccessForUser user d,d)) <$> theDocument


docApiV2Remind :: Kontrakcja m => DocumentID -> m Response
docApiV2Remind did = logDocument did . api $ do
  -- Permissions
  (user, actor) <- getAPIUser APIDocSend
  withDocumentID did $ do
    -- Guards
    guardThatUserIsAuthorOrCompanyAdmin user
    guardThatObjectVersionMatchesIfProvided did
    guardDocumentStatus Pending
    -- API call actions
    _ <- sendAllReminderEmailsExceptAuthor actor False
    -- Result
    return $ Accepted ()


docApiV2Forward :: Kontrakcja m => DocumentID -> m Response
docApiV2Forward did = logDocument did . api $ do
  -- Permissions
  (user,_) <- getAPIUser APIDocCheck
  withDocumentID did $ do
    -- Guards
    guardThatUserIsAuthor user
    guardThatObjectVersionMatchesIfProvided did
    -- Make sure we only send out the document with the author's signatory link
    -- when it is closed, otherwise the link may be abused
    guardDocumentStatus Closed
    -- Parameters
    email <- T.unpack <$> apiV2ParameterObligatory (ApiV2ParameterText "email")
    noContent <- apiV2ParameterDefault True (ApiV2ParameterBool "no_content")
    -- API call actions
    asiglink <- $fromJust <$> getAuthorSigLink <$> theDocument
    validEmail <- case asValidEmail email of
      Good em -> return em
      _ -> apiError $ requestParameterInvalid "email" "Not a valid email address"
    _ <- sendForwardEmail validEmail noContent asiglink
    -- Return
    return $ Accepted ()


docApiV2SetFile :: Kontrakcja m => DocumentID -> m Response
docApiV2SetFile did = logDocument did . api $ do
  -- Permissions
  (user, actor) <- getAPIUser APIDocCreate
  withDocumentID did $ do
    -- Guards
    guardThatUserIsAuthor user
    guardThatObjectVersionMatchesIfProvided did
    guardDocumentStatus Preparation
    -- Parameters
    mFile <- apiV2ParameterOptional (ApiV2ParameterFilePDF "file")
    -- API call actions
    case mFile of
      Nothing -> dbUpdate $ DetachFile actor
      Just file -> do
        dbUpdate $ AttachFile (fileid file) actor
        moldfileid <- fmap mainfileid <$> documentfile <$> theDocument
        case moldfileid of
          Just oldfileid -> recalcuateAnchoredFieldPlacements oldfileid (fileid file)
          Nothing -> return ()
    -- Result
    Ok <$> (\d -> (unjsonDocument $ documentAccessForUser user d,d)) <$> theDocument


docApiV2SetAttachments :: Kontrakcja m => DocumentID -> m Response
docApiV2SetAttachments did = logDocument did . api $ do
  -- Permissions
  (user, actor) <- getAPIUser APIDocCreate
  withDocumentID did $ do
    -- Guards
    guardThatUserIsAuthor user
    guardThatObjectVersionMatchesIfProvided did
    guardDocumentStatus Preparation
    -- Parameters
    attachments <- processAttachmentParameters
    (mFileIDsInt :: Maybe [Int]) <- apiV2ParameterOptional (ApiV2ParameterAeson "file_ids")
    let mFileIDs :: Maybe [FileID] = fmap ($read . show) mFileIDsInt
    fileIDs <- case mFileIDs of
      Nothing -> return []
      Just fids -> do
        doc <- theDocument
        forM fids (\fid -> do
          let fidAlreadyInDoc = fid `elem` (authorattachmentfileid <$> documentauthorattachments doc)
          hasAccess <- (not null) <$> dbQuery (attachmentsQueryFor user fid)
          when (not (fidAlreadyInDoc || hasAccess)) $
            apiError $ resourceNotFound $ "No file with file_id" <+> (T.pack . show $ fid)
              <+> "found. It may not exist or you don't have permission to use it."
          return fid
          )
    let allAttachments = fileIDs ++ attachments
    -- API call actions
    (documentauthorattachments <$> theDocument >>=) $ mapM_ $ \att -> dbUpdate $ RemoveDocumentAttachment (authorattachmentfileid att) actor
    forM_ allAttachments $ \att -> dbUpdate $ AddDocumentAttachment att actor
    -- Return
    Ok <$> (\d -> (unjsonDocument $ documentAccessForUser user d,d)) <$> theDocument

  where
    processAttachmentParameters :: (Kontrakcja m) => m [FileID]
    processAttachmentParameters = sequenceOfFileIDsWith getAttachmentParmeter [] 0
    getAttachmentParmeter :: (Kontrakcja m) => Int -> m (Maybe FileID)
    getAttachmentParmeter i = (fmap fileid) <$> apiV2ParameterOptional (ApiV2ParameterFilePDF $ "attachment_" <> (T.pack . show $ i))
    sequenceOfFileIDsWith :: (Kontrakcja m) => (Int -> m (Maybe FileID)) -> [FileID] -> Int -> m [FileID]
    sequenceOfFileIDsWith fidFunc lf i = do
      mAttachment <- fidFunc i
      case mAttachment of
        Nothing -> return lf
        Just attachment -> do
          let attList | attachment `elem` lf = lf
                      | otherwise            = attachment : lf
          sequenceOfFileIDsWith fidFunc attList (i + 1)

    attachmentsQueryFor user fid = GetAttachments [ AttachmentsSharedInUsersCompany (userid user)
                                                  , AttachmentsOfAuthorDeleteValue  (userid user) True
                                                  , AttachmentsOfAuthorDeleteValue  (userid user) False
                                                  ]
                                                  [AttachmentFilterByFileID [fid]]
                                                  []
                                                  (0,1)


docApiV2SetAutoReminder :: Kontrakcja m => DocumentID -> m Response
docApiV2SetAutoReminder did = logDocument did . api $ do
  -- Permissions
  (user,_) <- getAPIUser APIDocSend
  withDocumentID did $ do
    -- Guards
    guardThatUserIsAuthor user
    guardThatObjectVersionMatchesIfProvided did
    guardDocumentStatus Pending
    -- Parameters
    daysParam <- apiV2ParameterOptional (ApiV2ParameterInt "days")
    days <- case daysParam of
      Nothing -> return Nothing
      Just d -> do
        ctx <- getContext
        tot <- documenttimeouttime <$> theDocument
        if d < 1 || (isJust tot && d `daysAfter` (ctxtime ctx) > $fromJust tot)
          then apiError $ requestParameterInvalid "days" "Must be a number between 1 and the number of days left to sign"
          else return $ Just d
    -- API call actions
    timezone <- documenttimezonename <$> theDocument
    setAutoreminder did (fmap fromIntegral days) timezone
    -- Result
    Ok <$> (\d -> (unjsonDocument $ documentAccessForUser user d,d)) <$> theDocument


docApiV2Clone :: Kontrakcja m => DocumentID -> m Response
docApiV2Clone did = logDocument did . api $ do
  -- Permissions
  (user, actor) <- getAPIUser APIDocCreate
  withDocumentID did $ do
    -- Guards
    guardThatUserIsAuthor user
    guardThatObjectVersionMatchesIfProvided did
    -- API call actions
    doc <- theDocument
    mNewDid <- dbUpdate $ CloneDocumentWithUpdatedAuthor user doc actor
    when (isNothing mNewDid) $
      apiError $ serverError "Could not clone document, did not get back valid ID"
    newdoc <- dbQuery $ GetDocumentByDocumentID $ $fromJust mNewDid
    -- Result
    return $ Created $ (\d -> (unjsonDocument $ documentAccessForUser user d,d)) newdoc


docApiV2Restart :: Kontrakcja m => DocumentID -> m Response
docApiV2Restart did = logDocument did . api $ do
  -- Permissions
  (user, actor) <- getAPIUser APIDocCreate
  withDocumentID did $ do
    -- Guards
    guardThatUserIsAuthor user
    guardThatObjectVersionMatchesIfProvided did
    guardThatDocumentIs (\d -> not $ documentstatus d `elem` [Preparation, Pending, Closed])
      "Documents that are in Preparation, Pending, or Closed can not be restarted."
    -- API call actions
    doc <- theDocument
    mNewDoc <- dbUpdate $ RestartDocument doc actor
    when (isNothing mNewDoc) $
      apiError $ serverError "Could not restart document"
    -- Result
    return $ Created $ (\d -> (unjsonDocument $ documentAccessForUser user d,d)) ($fromJust mNewDoc)

docApiV2SigSetAuthenticationToSign :: Kontrakcja m => DocumentID -> SignatoryLinkID -> m Response
docApiV2SigSetAuthenticationToSign did slid = logDocumentAndSignatory did slid . api $ do
  -- Permissions
  (user, actor) <- getAPIUser APIDocSend
  withDocumentID did $ do
    -- Guards
    guardThatUserIsAuthorOrCompanyAdmin user
    guardThatObjectVersionMatchesIfProvided did
    guardDocumentStatus Pending
    guardSignatoryHasNotSigned slid
    -- Parameters
    authentication_type <- apiV2ParameterObligatory (ApiV2ParameterTextUnjson "authentication_type" unjsonAuthenticationToSignMethod)
    authentication_value <- (fmap T.unpack) <$> apiV2ParameterOptional (ApiV2ParameterText "authentication_value")
    -- API call actions
    dbUpdate $ ChangeAuthenticationToSignMethod slid authentication_type authentication_value actor
    -- Return
    Ok <$> (\d -> (unjsonDocument $ documentAccessForUser user d,d)) <$> theDocument
