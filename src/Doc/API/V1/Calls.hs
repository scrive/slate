module Doc.API.V1.Calls (
    documentAPIV1
  , apiCallV1CreateFromFile      -- Exported for tests
  , apiCallV1CreateFromTemplate  -- Exported for tests
  , apiCallV1Get                 -- Exported for tests
  , apiCallV1GetEvidenceAttachments -- Exported for tests
  , apiCallV1List                -- Exported for tests
  , apiCallV1Update              -- Exported for tests
  , apiCallV1Ready               -- Exported for tests
  , apiCallV1Sign                -- Exported for tests
  , apiCallV1Cancel              -- Exported for tests
  , apiCallV1Reject              -- Exported for tests
  , apiCallV1SetAutoReminder     -- Exported for tests
  , apiCallV1DownloadMainFile    -- Exported for tests
  , apiCallV1DownloadFile        -- Exported for tests
  , apiCallV1ChangeMainFile
  , apiCallV1ChangeAuthenticationToSign    -- Exported for tests
  , apiCallV1SetAuthorAttachemnts -- Exported for tests
  ) where

import Control.Conditional ((<|), (|>), whenM, unlessM, ifM)
import Control.Exception.Lifted
import Control.Monad.IO.Class
import Control.Monad.Trans.Control (MonadBaseControl)
import Data.Aeson (Value(..))
import Data.Char
import Data.Int
import Data.String.Utils (replace,splitWs, strip)
import Data.Time
import Happstack.Server.RqData
import Happstack.Server.Types
import Happstack.StaticRouting
import Log
import System.Exit
import System.FilePath.Posix (takeBaseName)
import Text.JSON hiding (Ok)
import Text.JSON.FromJSValue
import Text.JSON.String (runGetJSON)
import Text.StringTemplates.Templates
import qualified Data.ByteString.Base64 as B64
import qualified Data.ByteString.Char8 as BS
import qualified Data.ByteString.Lazy as BSL
import qualified Data.ByteString.Lazy.UTF8 as BSL
import qualified Data.ByteString.UTF8 as BS hiding (length)
import qualified Data.HashMap.Strict as Hash
import qualified Data.Map as Map hiding (map)
import qualified Data.Traversable as T
import qualified Data.Vector as Vec
import qualified Text.JSON as J
import qualified Text.JSON.Gen as J
import qualified Text.JSON.Pretty as J (pp_value)

import API.Monad
import AppView (respondWithPDF)
import Attachment.Model
import DB
import DB.TimeZoneName (mkTimeZoneName, defaultTimeZoneName)
import Doc.Action
import Doc.Anchors
import Doc.API.Callback.Model
import Doc.API.V1.DocumentFromJSON()
import Doc.API.V1.DocumentToJSON
import Doc.API.V1.DocumentUpdateUtils
import Doc.AutomaticReminder.Model
import Doc.Conditions
import Doc.DocControl
import Doc.DocInfo
import Doc.DocMails
import Doc.DocSeal as DocSeal
import Doc.DocStateData
import Doc.DocStateQuery
import Doc.DocumentID
import Doc.DocumentMonad (DocumentMonad, withDocument, withDocumentID, withDocumentM, theDocument)
import Doc.DocUtils
import Doc.Logging
import Doc.Model
import Doc.Rendering
import Doc.SealStatus (SealStatus(..))
import Doc.SignatoryLinkID
import Doc.SignatoryScreenshots(SignatoryScreenshots, emptySignatoryScreenshots, resolveReferenceScreenshotNames)
import Doc.SMSPin.Model
import Doc.Tokens.Model
import EID.Signature.Model
import EvidenceLog.Control
import File.File
import File.Model
import File.Storage
import Happstack.Fields
import InputValidation
import Kontra
import KontraPrelude
import ListUtil
import LiveDocx
import Log.Utils
import MagicHash (MagicHash)
import MinutesTime
import OAuth.Model
import Routing
import Text.JSON.Convert
import User.Model
import User.UserView
import User.Utils
import Util.Actor
import Util.CSVUtil
import Util.HasSomeUserInfo
import Util.SignatoryLinkUtils
import Utils.Directory
import Utils.IO
import Utils.Monad
import qualified Data.ByteString.RFC2397 as RFC2397

documentAPIV1 ::  Route (Kontra Response)
documentAPIV1  = choice [

  dir "createfromfile"     $ hPost $ toK0 $ apiCallV1CreateFromFile,
  dir "createfromtemplate" $ hPostAllowHttp $ toK1 $ apiCallV1CreateFromTemplate,
  dir "clone"              $ hPost $ toK1   $  apiCallV1Clone,
  dir "update"             $ hPost $ toK1 $ apiCallV1Update,
  dir "setattachments"     $ hPost $ toK1 $ apiCallV1SetAuthorAttachemnts,
  dir "ready"              $ hPostAllowHttp $ toK1 $ apiCallV1Ready,
  dir "cancel"             $ hPost $ toK1 $ apiCallV1Cancel,
  dir "reject"             $ hPost $ toK2 $ apiCallV1Reject,
  dir "checksign"          $ hPost $ toK2 $ apiCallV1CheckSign,
  dir "sign"               $ hPost $ toK2 $ apiCallV1Sign,

  dir "sendsmspin"            $ hPost $ toK2 $ apiCallV1SendSMSPinCode,

  dir "restart"              $ hPost $ toK1 $ apiCallV1Restart,
  dir "prolong"              $ hPost $ toK1 $ apiCallV1Prolong,
  dir "setautoreminder"      $ hPost $ toK1 $ apiCallV1SetAutoReminder,
  dir "changeauthentication" $ hPost $ toK2 $ apiCallV1ChangeAuthenticationToSign,


  dir "remind"             $ hPost $ toK1 $ apiCallV1Remind,
  dir "forward"            $ hPost $ toK1 $ apiCallV1Forward,
  dir "delete"             $ hDeleteAllowHttp  $ toK1 $ apiCallV1Delete,
  dir "reallydelete"       $ hDeleteAllowHttp  $ toK1 $ apiCallV1ReallyDelete,
  dir "get"                $ hGetAllowHttp $ toK1 $ apiCallV1Get,
  dir "getevidenceattachments" $ hGet $ toK1 $ apiCallV1GetEvidenceAttachments,

  dir "list"               $ hGetAllowHttp $ apiCallV1List,
  dir "checkavailable"     $ hPostAllowHttp $ apiCallV1CheckAvailable,

  dir "history"           $ hGetAllowHttp $ apiCallV1History,
  dir "downloadmainfile"   $ hGetAllowHttp  $ toK2 $ apiCallV1DownloadMainFile,
  dir "downloadfile"       $ hGetAllowHttp  $ toK3 $ apiCallV1DownloadFile,
  dir "extracttexts"       $ hGetAllowHttp  $ toK2 $ apiCallV1ExtractTexts,

  dir "changemainfile"     $ hPost $ toK1 $ apiCallV1ChangeMainFile,

  dir "documentbrandingforsignview" $ hGet $ toK2 $ apiCallV1GetBrandingForSignView,

  dir "setsignatoryattachment"    $ hPost $ toK3 $ apiCallV1SetSignatoryAttachment
  ]

-- | Windows Explorer set the full path of a file, for example:
--
--    c:\My Documents\Things\Untitle Document.doc
--
-- We drop all up to and including last backslash here.
dropFilePathFromWindows :: FilePath -> FilePath
dropFilePathFromWindows = reverse . takeWhile (/='\\') . reverse

{- New API calls-}
apiCallV1CreateFromFile :: Kontrakcja m => m Response
apiCallV1CreateFromFile = api $ do
  ctx <- getContext
  (user, actor, external) <- getAPIUser APIDocCreate
  isTpl <- isFieldSet "template"
  let doctype = (Template <| isTpl |> Signable)
  minput <- getDataFn' (lookInput "file")
  (mfile, title) <- case minput of
    Nothing -> do
      title <- renderTemplate_ ("newDocumentTitle" <| not isTpl |> "newTemplateTitle")
      return (Nothing,  replace "  " " " $ title ++ " " ++ formatTimeSimple (ctxtime ctx))
    Just (Input _ Nothing _) -> throwIO . SomeKontraException $ badInput "Missing file"
    Just (Input contentspec (Just filename'') _contentType) -> do
      let filename' = dropFilePathFromWindows filename''
      let mformat = getFileFormatForConversion filename'
      content1' <- case contentspec of
        Left filepath -> liftIO $ BS.readFile filepath
        Right content -> return (BS.concat $ BSL.toChunks content)

      -- This is some kind of Salesforce hack that was supposed to be
      -- dropped with Happstack 7.0.4. It seems to be used till now
      -- for example by Avis.
      let content' = either (const content1') id (B64.decode content1')
      (content'', filename) <- case mformat of
        Nothing -> return (content', filename')
        Just format -> do
          eres <- convertToPDF (ctxlivedocxconf ctx) content' format
          case eres of
            Left (LiveDocxIOError e) -> throwIO . SomeKontraException $ serverError $ show e
            Left (LiveDocxSoapError s)-> throwIO . SomeKontraException $ serverError s
            Right res -> do
              -- change extension from .doc, .docx and others to .pdf
              let filename = takeBaseName filename' ++ ".pdf"
              return $ (res, filename)

      pdfcontent <- apiGuardL (badInput "The PDF is invalid.") $ preCheckPDF content''
      fileid' <- dbUpdate $ NewFile filename pdfcontent
      return (Just fileid', takeBaseName filename)
  mtimezone <- getField "timezone"
  timezone <- fromMaybe defaultTimeZoneName <$> T.sequence (mkTimeZoneName <$> mtimezone)
  (dbUpdate $ NewDocument user title doctype timezone 0 actor) `withDocumentM` do
    when_ (not $ external) $ dbUpdate $ SetDocumentUnsavedDraft True
    case mfile of
      Nothing -> return ()
      Just fileid' -> do
        dbUpdate $ AttachFile fileid' actor
    Created <$> (documentJSONV1 (Just user) True True Nothing =<< theDocument)

apiCallV1CreateFromTemplate :: Kontrakcja m => DocumentID -> m Response
apiCallV1CreateFromTemplate did = logDocument did . api $ do
  (user, actor, external) <- getAPIUser APIDocCreate
  template <- dbQuery $ GetDocumentByDocumentID $ did
  auid <- apiGuardJustM (serverError "No author found") $ return $ join $ maybesignatory <$> getAuthorSigLink template
  auser <- apiGuardJustM (serverError "No user found") $ dbQuery $ GetUserByIDIncludeDeleted auid
  let haspermission = (userid auser == userid user) ||
                      (usercompany auser == usercompany user &&  isDocumentShared template)
  unless (isTemplate template && haspermission) $ do
    throwIO $ SomeKontraException $ serverError "Id did not matched template or you do not have right to access document"
  when (documentDeletedForUser template $ userid user) $
    throwIO $ SomeKontraException $ serverError "Template is deleted"
  (apiGuardJustM (serverError "Can't clone given document") (dbUpdate $ CloneDocumentWithUpdatedAuthor user template actor) >>=) $ flip withDocumentID $ do
    dbUpdate $ DocumentFromTemplate actor
    when_ (not $ external) $ dbUpdate $ SetDocumentUnsavedDraft True
    Created <$> (documentJSONV1 (Just user) True True Nothing =<< theDocument)

apiCallV1Clone :: Kontrakcja m => DocumentID -> m Response
apiCallV1Clone did = logDocument did . api $ do
  (user, actor, _) <- getAPIUser APIDocCreate
  doc <- dbQuery $ GetDocumentByDocumentID $ did
  if isAuthor (doc,user)
     then do
         mndid <- dbUpdate $ CloneDocumentWithUpdatedAuthor user doc actor
         when (isNothing mndid) $
             throwIO . SomeKontraException $ serverError "Can't clone given document"
         newdoc <- dbQuery $ GetDocumentByDocumentID $ $fromJust mndid
         Created <$> documentJSONV1 (Just $ user) True  True Nothing newdoc
     else throwIO . SomeKontraException $ serverError "Id did not matched template or you do not have right to access document"

apiCallV1Update :: Kontrakcja m => DocumentID -> m Response
apiCallV1Update did = logDocument did . api $ do
  (user, actor, _) <- getAPIUser APIDocCreate
  withDocumentID did $ do
    auid <- apiGuardJustM (serverError "No author found") $ ((maybesignatory =<<) . getAuthorSigLink) <$> theDocument
    unlessM (isPreparation <$> theDocument) $ do
          checkObjectVersionIfProvidedAndThrowError did (serverError "Document is not a draft or template")
    when (not $ (auid == userid user)) $ do
          throwIO . SomeKontraException $ serverError "Permission problem. Not an author."
    jsons <- apiGuardL (badInput "The MIME part 'json' must exist and must be a JSON.") $ getDataFn' (look "json")
    json <- apiGuard (badInput "The MIME part 'json' must be a valid JSON.") $ case decode jsons of
                                                                                 J.Ok js -> Just js
                                                                                 _ -> Nothing
    logInfo "Document updated" $ trimDocumentJSON $ jsonToAeson json
    draftData   <- apiGuardJustM (badInput "Given JSON does not represent valid draft data.") $ flip fromJSValueWithUpdate json . Just <$> theDocument
    whenM (draftIsChangingDocument draftData <$> theDocument) $ do
      checkObjectVersionIfProvided did -- If we will change document, then we want to be sure that object version is ok.
    applyDraftDataToDocument draftData actor
    Ok <$> (documentJSONV1 (Just user) True True Nothing =<< theDocument)
  where trimDocumentJSON (Object o) = Object $ Hash.adjust trimSignatoriesJSON "signatories" o
        trimDocumentJSON x = x

        trimSignatoriesJSON (Array a) = Array $ (Vec.map trimSignatoryJSON) a
        trimSignatoriesJSON x = x

        trimSignatoryJSON (Object o) = Object $ Hash.adjust trimCSVJSON "csv" o
        trimSignatoryJSON x = x

        trimCSVJSON Null = Null
        trimCSVJSON _ = String $ "(Omitted for logs)"

apiCallV1SetAuthorAttachemnts  :: Kontrakcja m => DocumentID -> m Response
apiCallV1SetAuthorAttachemnts did = logDocument did . api $ do
  (user, actor, _) <- getAPIUser APIDocCreate
  withDocumentID did $ do
    auid <- apiGuardJustM (serverError "No author found") $ ((maybesignatory =<<) . getAuthorSigLink) <$> theDocument
    unlessM (isPreparation <$> theDocument) $ do
          checkObjectVersionIfProvidedAndThrowError did (serverError "Document is not a draft or template")
    when (not $ (auid == userid user)) $ do
          throwIO . SomeKontraException $ serverError "Permission problem. Not an author."
    attachments <- getAttachments 0 =<< theDocument
    (documentauthorattachments <$> theDocument >>=) $ mapM_ $ \att -> dbUpdate $ RemoveDocumentAttachment (authorattachmentfileid att) actor
    forM_ attachments $ \att -> dbUpdate $ AddDocumentAttachment att actor
    Ok <$> (documentJSONV1 (Just user) True True Nothing =<< theDocument)
     where
          getAttachments :: Kontrakcja m => Int -> Document -> m [FileID]
          getAttachments i doc = do
              mf <- tryGetFile doc i
              case mf of
                   Just f -> do
                              atts <- getAttachments (i+1) doc
                              if (f `elem` atts)
                                then return atts
                                else return $ f: atts
                   Nothing -> return []
          tryGetFile ::  Kontrakcja m => Document -> Int -> m  (Maybe FileID)
          tryGetFile doc i = do
              inp <- getDataFn' (lookInput $ "attachment_" ++ show i)
              case inp of
                   Just (Input (Left filepath) (Just filename) _contentType) -> do
                       content <- liftIO $ BSL.readFile filepath
                       cres <- preCheckPDF (BSL.toStrict content)
                       case cres of
                         Left _ -> do
                           throwIO . SomeKontraException $ (badInput $ "AttachFile " ++ show i ++ " file is not a valid PDF")
                         Right content' -> do
                           fileid' <- dbUpdate $ NewFile filename content'
                           return (Just fileid')
                   Just (Input  (Right c)  _ _)  -> do
                        case maybeRead (BSL.toString c) of
                            Just fid -> do
                              access <- hasAccess doc fid
                              if access
                                then return (Just fid)
                                else throwIO . SomeKontraException $ (forbidden $ "Access to attachment " ++ show i ++ " forbiden")
                            Nothing -> throwIO . SomeKontraException $ (badInput $ "Can parse attachment id for attachment " ++ show i)
                   _ -> return Nothing

          hasAccess ::  Kontrakcja m => Document -> FileID -> m Bool
          hasAccess doc fid = do
            user <- $fromJust <$> ctxmaybeuser <$> getContext
            if (fid `elem` (authorattachmentfileid <$> documentauthorattachments doc))
             then return True
             else do
              atts <-  dbQuery $ GetAttachments [  AttachmentsSharedInUsersCompany (userid user)
                                                , AttachmentsOfAuthorDeleteValue (userid user) True
                                                , AttachmentsOfAuthorDeleteValue (userid user) False
                                               ]
                                              [ AttachmentFilterByFileID [fid]]
                                              []
                                              (0,1)
              return $ not $ null atts

apiCallV1Ready :: (MonadBaseControl IO m, Kontrakcja m) => DocumentID -> m Response
apiCallV1Ready did = logDocument did . api $ do
  (user, actor, _) <- getAPIUser APIDocSend
  withDocumentID did $ do
    auid <- apiGuardJustM (serverError "No author found") $ ((maybesignatory =<<) .getAuthorSigLink) <$> theDocument
    ifM ((isPending  && not . any hasSigned . documentsignatorylinks) <$> theDocument)
     {-then-} (Accepted <$> (documentJSONV1 (Just user) True True Nothing =<< theDocument))
     {-else-} $ do
      checkObjectVersionIfProvided did
      when (not $ (auid == userid user)) $ do
            throwIO . SomeKontraException $ serverError "Permission problem. Not an author."
      unlessM (isPreparation <$> theDocument) $ do
            checkObjectVersionIfProvidedAndThrowError did $ (conflictError "Document is not a draft")
      whenM (isTemplate <$> theDocument) $ do
            checkObjectVersionIfProvidedAndThrowError did $ (serverError "Document is not a draft")
      unlessM (((all signatoryHasValidDeliverySettings) . documentsignatorylinks) <$> theDocument) $ do
            throwIO . SomeKontraException $ serverError "Some signatories have invalid email address or phone number, and it is required for invitation delivery."
      unlessM (((all signatoryHasValidAuthSettings) . documentsignatorylinks) <$> theDocument) $ do
            throwIO . SomeKontraException $ serverError "Some signatories have invalid personal number, and it is required for authentication."
      unlessM (((all signatoryHasValidSSNForIdentifyToView) . documentsignatorylinks) <$> theDocument) $ do
            throwIO . SomeKontraException $ serverError "Some signatories have invalid personal number and it is required for identification to view document."
      whenM (isNothing . documentfile <$> theDocument) $ do
            throwIO . SomeKontraException $ serverError "File must be provided before document can be made ready."
      t <- ctxtime <$> getContext
      timezone <- documenttimezonename <$> theDocument
      dbUpdate $ PreparationToPending actor timezone
      dbUpdate $ SetDocumentInviteTime t actor
      authorsignsimmediately <- isFieldSet "authorsignsimmediately"
      postDocumentPreparationChange authorsignsimmediately timezone
      Accepted <$> (documentJSONV1 (Just user) True True Nothing =<< theDocument)
  where
    signatoryHasValidDeliverySettings sl = (isAuthor sl) || case (signatorylinkdeliverymethod sl) of
      EmailDelivery  ->  isGood $ asValidEmail $ getEmail sl
      MobileDelivery ->  isGood $ asValidPhoneForSMS $ getMobile sl
      EmailAndMobileDelivery -> (isGood $ asValidPhoneForSMS $ getMobile sl) && (isGood $ asValidEmail $ getEmail sl)
      _ -> True
    signatoryHasValidAuthSettings sl = authToSignIsValid sl
    authToSignIsValid sl = getPersonalNumber sl == "" || case signatorylinkauthenticationtosignmethod sl of
      SEBankIDAuthenticationToSign -> isGood $ asValidSEBankIdPersonalNumber $ getPersonalNumber sl
      _ -> True
    signatoryHasValidSSNForIdentifyToView sl = case (signatorylinkauthenticationtoviewmethod sl) of
      SEBankIDAuthenticationToView  ->  isGood $ asValidSwedishSSN $ getPersonalNumber sl
      NOBankIDAuthenticationToView ->   isGood $ asValidNorwegianSSN $ getPersonalNumber sl
      _ -> True

apiCallV1Cancel :: (MonadBaseControl IO m, Kontrakcja m) =>  DocumentID -> m Response
apiCallV1Cancel did = logDocument did . api $ do
    checkObjectVersionIfProvided did
    (user, actor, _) <- getAPIUser APIDocSend
    withDocumentID did $ do
      guardAuthorOrAuthorsAdmin user "Permission problem. You don't have a permission to cancel this document"
      unlessM (isPending <$> theDocument) $ do
            throwIO . SomeKontraException $ (conflictError "Document is not pending")
      dbUpdate $ CancelDocument actor
      postDocumentCanceledChange =<< theDocument
      Accepted <$> (documentJSONV1 (Just user) True True Nothing =<< theDocument)

apiCallV1Reject :: (MonadBaseControl IO m, Kontrakcja m) =>  DocumentID -> SignatoryLinkID -> m Response
apiCallV1Reject did slid = logDocumentAndSignatory did slid . api $ do
  checkObjectVersionIfProvided did
  (mh,mu) <- getMagicHashAndUserForSignatoryAction did slid
  dbQuery (GetDocumentByDocumentIDSignatoryLinkIDMagicHash did slid mh) `withDocumentM` do
    ctx <- getContext
    Just sll <- getSigLinkFor slid <$> theDocument
    customtext <- fmap strip <$> getField "customtext"
    switchLang . getLang =<< theDocument
    (dbUpdate . RejectDocument slid customtext =<< signatoryActor ctx sll)
        `catchKontra` (\(DocumentStatusShouldBe _ _ i) -> throwIO . SomeKontraException $ conflictError $ "Document not pending but " ++ show i)
        `catchKontra` (\(SignatoryHasAlreadySigned {}) -> throwIO . SomeKontraException $ conflictError $ "Signatory has already signed")
    postDocumentRejectedChange slid customtext =<< theDocument
    Accepted <$> (documentJSONV1 mu True True Nothing =<< theDocument)

apiCallV1CheckSign :: Kontrakcja m
             => DocumentID      -- ^ The DocumentID of the document to sign
             -> SignatoryLinkID -- ^ The SignatoryLinkID that is in the URL
             -> m Response
apiCallV1CheckSign did slid = logDocumentAndSignatory did slid . api $ do
  checkObjectVersionIfProvided did

  (mh,_) <- getMagicHashAndUserForSignatoryAction did slid

  (dbQuery $ GetDocumentByDocumentIDSignatoryLinkIDMagicHash did slid mh) `withDocumentM` do
    whenM (not <$> isPending <$> theDocument ) $ do
      (throwIO . SomeKontraException $ conflictError $ "Document not pending")
    whenM (hasSigned <$> $fromJust . getSigLinkFor slid <$> theDocument) $ do -- We can use fromJust since else we would not get access to document
      (throwIO . SomeKontraException $ conflictError $ "Document already signed")
    whenM (signatoryNeedsToIdentifyToView =<< $fromJust . getSigLinkFor slid <$> theDocument) $ do
      (throwIO . SomeKontraException $ forbidden "Authorization to view is needed")
    checkAuthenticationToSignMethodAndValue slid
    authorization <- signatorylinkauthenticationtosignmethod <$> $fromJust . getSigLinkFor slid <$> theDocument
    fields <- getFieldForSigning
    case authorization of
       StandardAuthenticationToSign -> return $ Right $ Ok () -- If we have a document with standard auth, it can be always signed if its not closed and signed
       SMSPinAuthenticationToSign -> do
             validPin <- getValidPin slid fields
             if (isJust validPin)
               then return $ Right $ Ok ()
               else (Left . Failed) <$> (J.runJSONGenT $ J.value "pinProblem" True)
       SEBankIDAuthenticationToSign -> dbQuery (GetESignature slid) >>= \case
         Just _ -> return $ Right $ Ok ()
         Nothing -> do
           logInfo_ "No e-signature found for a signatory"
           return . Left . Failed $ J.runJSONGen $ J.value "noSignature" True

apiCallV1Sign :: Kontrakcja m
             => DocumentID      -- ^ The DocumentID of the document to sign
             -> SignatoryLinkID -- ^ The SignatoryLinkID that is in the URL
             -> m Response
apiCallV1Sign did slid = logDocumentAndSignatory did slid . api $ do
  checkObjectVersionIfProvided did
  logInfo_ "Ready to sign a document for signatory"
  (mh,mu) <- getMagicHashAndUserForSignatoryAction did slid
  screenshots' <- fmap (fromMaybe emptySignatoryScreenshots) $
               (fromJSValue =<<) <$> getFieldJSON "screenshots"
  screenshots <- resolveReferenceScreenshotNames screenshots'
  fields <- getFieldForSigning
  olddoc <- dbQuery $ GetDocumentByDocumentIDSignatoryLinkIDMagicHash did slid mh -- We store old document, as it is needed by postDocumentXXX calls
  olddoc `withDocument` ( do
    whenM (not <$> isPending <$> theDocument ) $ do
      (throwIO . SomeKontraException $ conflictError $ "Document not pending")
    whenM (hasSigned <$> $fromJust . getSigLinkFor slid <$> theDocument) $ do -- We can use fromJust since else we would not get access to document
      (throwIO . SomeKontraException $ conflictError $ "Document already signed")
    whenM (signatoryNeedsToIdentifyToView =<< $fromJust . getSigLinkFor slid <$> theDocument) $ do
      (throwIO . SomeKontraException $ forbidden "Authorization to view is needed")
    checkAuthenticationToSignMethodAndValue slid
    authorization <- signatorylinkauthenticationtosignmethod <$> $fromJust . getSigLinkFor slid <$> theDocument

    case authorization of
      StandardAuthenticationToSign -> do
        signDocument slid mh fields Nothing Nothing screenshots
        postDocumentPendingChange olddoc
        handleAfterSigning slid
        (Right . Accepted) <$> (documentJSONV1 mu True True Nothing =<< theDocument)

      SMSPinAuthenticationToSign -> do
        validPin <- getValidPin slid fields
        if (isJust validPin)
          then do
            signDocument slid mh fields Nothing validPin screenshots
            postDocumentPendingChange olddoc
            handleAfterSigning slid
            (Right . Accepted) <$> (documentJSONV1 mu True True Nothing =<< theDocument)
          else (Left . Failed) <$> (J.runJSONGenT $ return ())

      SEBankIDAuthenticationToSign -> dbQuery (GetESignature slid) >>= \case
        mesig@(Just _) -> do
          signDocument slid mh fields mesig Nothing screenshots
          postDocumentPendingChange olddoc
          handleAfterSigning slid
          (Right . Accepted) <$> (documentJSONV1 mu True True Nothing =<< theDocument)
        Nothing -> do
          logInfo_ "No e-signature found for a signatory"
          return . Left . Failed $ J.runJSONGen $ J.value "noSignature" True
   )
    `catchKontra` (\(DocumentStatusShouldBe _ _ i) -> throwIO . SomeKontraException $ conflictError $ "Document not pending but " ++ show i)
    `catchKontra` (\(SignatoryHasAlreadySigned {}) -> throwIO . SomeKontraException $ conflictError $ "Signatory has already signed")

{- | Utils for signing with eleg -}
checkAuthenticationToSignMethodAndValue :: (Kontrakcja m, DocumentMonad m) => SignatoryLinkID -> m ()
checkAuthenticationToSignMethodAndValue slid = do
  mAuthType  :: Maybe String <- getField "authentication_type"
  mAuthValue :: Maybe String <- getField "authentication_value"
  case (mAuthType, mAuthValue) of
       (Just authType, Just authValue) -> do
           let mAuthMethod = fromJSValue $ J.toJSValue authType
           case mAuthMethod of
                Just authMethod -> do
                    siglink <- $fromJust . getSigLinkFor slid <$> theDocument
                    let authOK = authMethod == signatorylinkauthenticationtosignmethod siglink
                    case (authOK, authMethod) of
                         (False, _) -> throwIO . SomeKontraException $
                             conflictError "`authentication_type` does not match"
                         (True, StandardAuthenticationToSign) -> return ()
                         (True, SEBankIDAuthenticationToSign)   ->
                             if (authValue == getPersonalNumber siglink || null (getPersonalNumber siglink))
                                then return ()
                                else throwIO . SomeKontraException $
                                    conflictError "`authentication_value` for personal number does not match"
                         (True, SMSPinAuthenticationToSign) ->
                             if (authValue == getMobile siglink || null (getMobile siglink))
                                then return ()
                                else throwIO . SomeKontraException $
                                    conflictError "`authentication_value` for phone number does not match"
                Nothing ->
                    throwIO . SomeKontraException $ badInput "`authentication_type` was not a valid"
       (Nothing, Nothing) -> return ()
       _ -> throwIO . SomeKontraException $ badInput "Only one of `authentication_type` and `authentication_value` provided"

signDocument :: (Kontrakcja m, DocumentMonad m)
             => SignatoryLinkID
             -> MagicHash
             -> [(FieldIdentity, FieldTmpValue)]
             -> Maybe ESignature
             -> Maybe String
             -> SignatoryScreenshots
             -> m ()
signDocument slid mh fields mesig mpin screenshots = do
  switchLang =<< getLang <$> theDocument
  ctx <- getContext
  -- Note that the second 'getSigLinkFor' call below may return a
  -- different result than the first one due to the field update, so
  -- don't attempt to replace the calls with a single call, or the
  -- actor identities may get wrong in the evidence log.
  fieldsWithFiles <- fieldsToFieldsWithFiles fields
  getSigLinkFor slid <$> theDocument >>= \(Just sl) -> dbUpdate . UpdateFieldsForSigning sl (fst fieldsWithFiles) (snd fieldsWithFiles) =<< signatoryActor ctx sl
  getSigLinkFor slid <$> theDocument >>= \(Just sl) -> dbUpdate . SignDocument slid mh mesig mpin screenshots =<< signatoryActor ctx sl

{- End of utils-}

apiCallV1Restart :: (MonadBaseControl IO m, Kontrakcja m) =>  DocumentID -> m Response
apiCallV1Restart did = logDocument did . api $ do
    checkObjectVersionIfProvided did
    (user, actor, _) <- getAPIUser APIDocSend
    doc <- dbQuery $ GetDocumentByDocumentID $ did
    auid <- apiGuardJustM (serverError "No author found") $ return $ join $ maybesignatory <$> getAuthorSigLink doc
    when (not $ (auid == userid user)) $ do
          throwIO . SomeKontraException $ serverError "Permission problem. Not an author."
    when (documentstatus doc `elem` [Pending,Preparation, Closed] ) $ do
          throwIO . SomeKontraException $ (conflictError "Document can not be restarted")
    newdocument <- apiGuardJustM (serverError "Document can't be restarted") $ dbUpdate $ RestartDocument doc actor
    Accepted <$> documentJSONV1 (Just $ user) True True Nothing newdocument

apiCallV1Prolong :: (MonadBaseControl IO m, Kontrakcja m) =>  DocumentID -> m Response
apiCallV1Prolong did = logDocument did . api $ do
    checkObjectVersionIfProvided did
    (user, actor, _) <- getAPIUser APIDocSend
    withDocumentID did $ do
      hasPermission <- isAuthorOrAuthorsAdmin user <$> theDocument
      when (not hasPermission) $
        throwIO . SomeKontraException $ serverError "Permission problem. Not an author[s admin]."
      unlessM (isTimedout <$> theDocument) $ do
            throwIO . SomeKontraException $ (conflictError "Document is not timedout")
      mdays <- getDefaultedField 1 asValidNumber "days"
      days <- case mdays of
           Nothing -> throwIO . SomeKontraException $ (badInput "Number of days to sign must be a valid number, between 1 and 90")
           Just n -> if (n < 1 || n > 90)
                              then throwIO . SomeKontraException $ (badInput "Number of days to sign must be a valid number, between 1 and 90")
                              else return n
      timezone <- documenttimezonename <$> theDocument
      dbUpdate $ ProlongDocument days timezone actor
      triggerAPICallbackIfThereIsOne =<< theDocument
      Accepted <$> (documentJSONV1 (Just user) True True Nothing =<< theDocument)


apiCallV1SetAutoReminder :: (MonadBaseControl IO m, Kontrakcja m) => DocumentID -> m Response
apiCallV1SetAutoReminder did = logDocument did . api $ do
    ctx <- getContext
    checkObjectVersionIfProvided did
    (user, _actor, _) <- getAPIUser APIDocSend
    withDocumentID did $ do
      auid <- apiGuardJustM (serverError "No author found") $ ((maybesignatory =<<) . getAuthorSigLink) <$> theDocument
      when (not $ (auid == userid user)) $ do
            throwIO . SomeKontraException $ serverError "Permission problem. Not an author."
      unlessM (isPending <$> theDocument) $ do
            throwIO . SomeKontraException $ (conflictError "Document is not pending")
      mdays <- getOptionalField asValidNumber "days"
      days <- case mdays of
           Nothing -> return Nothing
           Just n -> do tot <- documenttimeouttime <$> theDocument
                        if n < 1 || (isJust tot && n `daysAfter` (ctxtime ctx) > $fromJust tot)
                          then throwIO . SomeKontraException $ (badInput "Number of days to send autoreminder must be a valid number, between 1 and number of days left till document deadline")
                          else return $ Just (fromIntegral n :: Int32)
      timezone <- documenttimezonename <$> theDocument
      setAutoreminder did days timezone
      triggerAPICallbackIfThereIsOne =<< theDocument
      Accepted <$> (documentJSONV1 (Just $ user) True True Nothing =<< theDocument)

apiCallV1ChangeAuthenticationToSign :: Kontrakcja m => DocumentID -> SignatoryLinkID -> m Response
apiCallV1ChangeAuthenticationToSign did slid = logDocumentAndSignatory did slid . api $ do
  (user, actor, _) <- getAPIUser APIDocSend
  withDocumentID did $ do
      guardAuthorOrAuthorsAdmin user "Permission problem. You don't have a permission to change this document"
      -- Document status and input checks
      unlessM (isPending <$> theDocument) $
          throwIO . SomeKontraException $ badInput "Document status must be pending"
      siglink <- getSigLinkFor slid <$> theDocument
      when (isNothing siglink) $
          throwIO . SomeKontraException $ badInput $ "Signatory link id " ++ (show slid) ++ " not valid for document id " ++ (show did)
      when (maybe False (isJust . maybesigninfo) siglink) $
          throwIO . SomeKontraException $ badInput $ "Signatory link id " ++ (show slid) ++ " has already signed"
      -- Get the POST data and check it
      authentication_type <- getField "authentication_type"
      maybeAuthValue      <- getField "authentication_value"
      when (isNothing authentication_type) $
          throwIO . SomeKontraException $ badInput $ "`authentication_type` must be given. "
                                          ++ "Supported values are: `standard`, `eleg`, `sms_pin`."
      let authenticationMethod = case fromJSValue $ J.toJSValue $ fromMaybe "" authentication_type of
              Just am -> Right am
              Nothing -> Left $ fromMaybe "" authentication_type
      -- Change authentication method (if input is a valid method)
      case authenticationMethod of
           Right a -> do
               let viewMethod = signatorylinkauthenticationtoviewmethod ($fromJust siglink)
               when (viewMethod == NOBankIDAuthenticationToView && a == SEBankIDAuthenticationToSign) $
                   throwIO . SomeKontraException $ badInput $ "Can't mix Norwegian and Swedish Bank ID"
               dbUpdate $ ChangeAuthenticationToSignMethod slid a maybeAuthValue actor
           Left  a -> throwIO . SomeKontraException
                      $ badInput $ "Invalid authentication method: `" ++ a ++ "` was given. "
                        ++ "Supported values are: `standard`, `eleg`, `sms_pin`."
      Accepted <$> (documentJSONV1 (Just user) True True Nothing =<< theDocument)

apiCallV1Remind :: Kontrakcja m => DocumentID -> m Response
apiCallV1Remind did = logDocument did . api $ do
  (user, actor , _) <- getAPIUser APIDocSend
  withDocumentID did $ do
    unlessM (isPending <$> theDocument) $ do
          throwIO . SomeKontraException $ serverError "Can't send reminder for documents that are not pending"
    hasPermission <- isAuthorOrAuthorsAdmin user <$> theDocument
    when (not hasPermission) $
      throwIO . SomeKontraException $ serverError "Permission problem. Not an author[s admin]."
    _ <- sendAllReminderEmailsExceptAuthor actor False
    Accepted <$> (documentJSONV1 (Just user) True True Nothing =<< theDocument)

apiCallV1Forward :: Kontrakcja m => DocumentID -> m Response
apiCallV1Forward did = logDocument did . api $ do
  (user, _actor , _) <- getAPIUser APIDocCheck
  withDocumentID did $ do
    unlessM (isClosed <$> theDocument) $ do
          throwIO . SomeKontraException $ badInput "Only document that are signed can be forwarded"
    asiglink <- apiGuardJustM (serverError "No author found") $ getAuthorSigLink <$> theDocument
    auid <- apiGuardJustM (serverError "No author found") $ return $ maybesignatory asiglink
    when (not $ (auid == userid user)) $ do
          throwIO . SomeKontraException $ serverError "Permission problem. Not an author."
    email <- apiGuardJustM (badInput "Email adress is no valid.") $ getOptionalField  asValidEmail "email"
    noContent <- (== Just "true") <$> getField  "nocontent"
    _ <- sendForwardEmail email noContent asiglink -- Make sure we only send out the document with the author's signatory link when it is closed, otherwise the link may be abused
    Accepted <$> (documentJSONV1 (Just user) True True Nothing =<< theDocument)

apiCallV1Delete :: Kontrakcja m => DocumentID -> m Response
apiCallV1Delete did = logDocument did . api $ do
  (user, actor, _) <- getAPIUser APIDocSend
  withDocumentID did $ do
    mauser <- theDocument >>= \d -> case join $ maybesignatory <$> getAuthorSigLink d of
                         Just auid -> dbQuery $ GetUserByIDIncludeDeleted auid
                         _ -> return Nothing
    msl <- getSigLinkFor user <$> theDocument
    let haspermission = (isJust msl)
                     || (isJust mauser && usercompany ($fromJust mauser) == usercompany user && (useriscompanyadmin user))
    when (not haspermission) $ do
           throwIO . SomeKontraException $ serverError "Permission problem. Not connected to document."
    dbUpdate $ ArchiveDocument (userid user) actor

    Accepted <$> (J.runJSONGenT $ return ())


apiCallV1ReallyDelete :: Kontrakcja m => DocumentID -> m Response
apiCallV1ReallyDelete did = logDocument did . api $ do
  (user, actor, _) <- getAPIUser APIDocSend
  withDocumentID did $ do
    mauser <- theDocument >>= \d -> case join $ maybesignatory <$> getAuthorSigLink d of
                         Just auid -> dbQuery $ GetUserByIDIncludeDeleted auid
                         _ -> return Nothing
    msl <- getSigLinkFor user <$> theDocument
    let haspermission = (isJust msl)
                     || (isJust mauser && usercompany ($fromJust mauser) == usercompany user && (useriscompanyadmin user))
    when (not haspermission) $ do
           throwIO . SomeKontraException $ serverError "Permission problem. Not connected to document."
    dbUpdate $ ReallyDeleteDocument (userid user) actor

    Accepted <$> (J.runJSONGenT $ return ())



-- TODO test case to make sure apiCallV1Get does not update document version (MarkDocumentSeen case)
apiCallV1Get :: Kontrakcja m => DocumentID -> m Response
apiCallV1Get did = logDocument did . api $ do
  ctx <- getContext
  (msignatorylink :: Maybe SignatoryLinkID) <- readField "signatoryid"
  mmagichashh <- maybe (return Nothing) (dbQuery . GetDocumentSessionToken) msignatorylink
  withDocumentID did $ case (msignatorylink,mmagichashh) of
    (Just slid,Just mh) -> do
       sl <- apiGuardJustM  (serverError "No document found") $ getSigLinkFor slid <$> theDocument
       when (signatorymagichash sl /= mh) $ throwIO . SomeKontraException $ serverError "No document found"
       unlessM ((isTemplate || isPreparation || isClosed) <$> theDocument) $
         dbUpdate . MarkDocumentSeen (signatorylinkid sl) (signatorymagichash sl)
                       =<< signatoryActor ctx sl
       switchLang . getLang =<< theDocument

       Ok <$> (documentJSONV1 Nothing False False (Just sl) =<< theDocument)
    _ -> do
      (user, _actor, external) <- getAPIUser APIDocCheck
      msiglink <- getSigLinkFor user <$> theDocument
      unlessM (((const (isNothing msiglink)) || isPreparation || isClosed  || isTemplate) <$> theDocument) $ do
          let sl = $fromJust msiglink
          dbUpdate . MarkDocumentSeen (signatorylinkid sl) (signatorymagichash sl)
               =<< signatoryActor ctx sl

      mauser <- theDocument >>= \d -> case (join $ maybesignatory <$> getAuthorSigLink d) of
                     Just auid -> dbQuery $ GetUserByIDIncludeDeleted auid
                     _ -> return Nothing

      haspermission <- theDocument >>= \d -> return $
                          isJust msiglink
                       || (isJust mauser && usercompany ($fromJust mauser) == usercompany user && (useriscompanyadmin user || isDocumentShared d))
      if (haspermission)
        then do
          Ok <$> (documentJSONV1 (Just user) external ((userid <$> mauser) == (Just $ userid user)) msiglink =<< theDocument)
        else throwIO . SomeKontraException $ serverError "You do not have right to access document"

-- Return evidence attachments for document
apiCallV1GetEvidenceAttachments :: Kontrakcja m => DocumentID -> m Response
apiCallV1GetEvidenceAttachments did = logDocument did . api $ withDocumentID did $ do
  (user, _, _) <- getAPIUser APIDocCheck
  guardAuthorOrAuthorsAdmin user "Permission problem. You don't have a permission to access this document"
  Ok <$> (evidenceAttachmentsJSONV1 =<< theDocument)

apiCallV1List :: Kontrakcja m => m Response
apiCallV1List = api $ do
  (user@User{userid = uid}, _actor, _) <- getAPIUserWithPad APIDocCheck

  doctype <- getField' "documentType"
  params <- getListParams
  let (domain,filters1) = case doctype of
                          "Document"          -> ([DocumentsVisibleToUser uid]
                                                 ,[DocumentFilterDeleted False, DocumentFilterSignable, DocumentFilterUnsavedDraft False])
                          "Template"          -> ([DocumentsVisibleToUser uid]
                                                 ,[DocumentFilterDeleted False, DocumentFilterTemplate, DocumentFilterUnsavedDraft False])
                          "MyTemplate"        -> ([DocumentsVisibleToUser uid] -- Sometimes we want to show only templates that user can change
                                                 ,[DocumentFilterByAuthor uid, DocumentFilterDeleted False, DocumentFilterTemplate, DocumentFilterUnsavedDraft False])
                          "Rubbish"           -> ([DocumentsVisibleToUser uid]
                                                 ,[DocumentFilterDeleted True, DocumentFilterUnsavedDraft False])
                          "All"               -> ([DocumentsVisibleToUser uid],[DocumentFilterUnsavedDraft False])
                          "DocumentsForPad"   -> ([DocumentsVisibleToUser uid],[DocumentFilterByAuthor uid, DocumentFilterSignNowOnPad])
                          _ -> ([DocumentsVisibleToUser uid],[DocumentFilterDeleted False, DocumentFilterUnsavedDraft False])
      filters2 = concatMap fltSpec (listParamsFilters params)
      fltSpec ("time", tostr) = case reads tostr of
                                    (((Just from',Just to'),""):_) -> [DocumentFilterByMonthYearFrom from',DocumentFilterByMonthYearTo to']
                                    (((Nothing ,Just to'),""):_) -> [DocumentFilterByMonthYearTo to']
                                    (((Just from',Nothing),""):_)   -> [DocumentFilterByMonthYearFrom from']
                                    _ -> []
      fltSpec ("mtime", tostr) = case parseTimeISO tostr of
                                    Just mtime -> [DocumentFilterByModificationTimeAfter mtime]
                                    _ -> []
      fltSpec ("sender", tostr) = case reads tostr of
                                    ((suid,""):_) -> [DocumentFilterByAuthor suid]
                                    _ -> []
      fltSpec ("cansign", tostr) = case reads tostr of
                                    ((suid,""):_) -> [DocumentFilterByCanSign suid]
                                    _ -> []
      fltSpec ("status", scstr) = case reads scstr of
                                    ((statusclasss,""):_) -> [DocumentFilterByStatusClass statusclasss]
                                    _ -> []
      fltSpec _ = []
  tagsstr <- getField' "tags"
  let tagsFilters = case runGetJSON readJSArray tagsstr of
                      Right js ->[DocumentFilterByTags $ join $ maybeToList $ (fromJSValueCustomMany fromJSValue js)]
                      _ -> []
  let sorting    = docSortingFromParams params
      searching  = docSearchingFromParams params
      pagination = (listParamsOffset params, listParamsLimit params, docsPageSize)
      filters = filters1 ++ filters2 ++ tagsFilters

  format <- getField "format"
  case format of
       Just "csv" -> do
          allDocs <- dbQuery $ GetDocuments domain (searching ++ filters) sorting (0, 1000)
          let docsCSVs = concat $ zipWith docForListCSVV1  [1..] allDocs
          return $ Left $ CSV { csvFilename = "documents.csv"
                              , csvHeader = docForListCSVHeaderV1
                              , csvContent = docsCSVs
                              }
       _ -> do
          (allDocsCount, allDocs) <- dbQuery $ GetDocumentsWithSoftLimit domain (searching ++ filters) sorting pagination
          let docs = PagedList {  list       = allDocs
                                , params     = params
                                , pageSize   = docsPageSize
                                , listLength = allDocsCount
                                }
          docsJSONs <- mapM (docForListJSONV1 user) $ list docs
          return $ Right $ J.runJSONGen $ do
              J.value "list" docsJSONs
              J.value "paging" $ pagingParamsJSON docs
  where
    docSortingFromParams :: ListParams -> [AscDesc DocumentOrderBy]
    docSortingFromParams params =
      (concatMap x (listParamsSorting params)) ++ [Desc DocumentOrderByMTime] -- default order by mtime
      where
        x "status"            = [Asc DocumentOrderByStatusClass]
        x "statusREV"         = [Desc DocumentOrderByStatusClass]
        x "title"             = [Asc DocumentOrderByTitle]
        x "titleREV"          = [Desc DocumentOrderByTitle]
        x "time"              = [Asc DocumentOrderByMTime]
        x "timeREV"           = [Desc DocumentOrderByMTime]
        x "party"             = [Asc DocumentOrderByPartners]
        x "partyREV"          = [Desc DocumentOrderByPartners]
        x "partner"           = [Asc DocumentOrderByPartners]
        x "partnerREV"        = [Desc DocumentOrderByPartners]
        x "type"              = [Asc DocumentOrderByType]
        x "typeREV"           = [Desc DocumentOrderByType]
        x "author"            = [Asc DocumentOrderByAuthor]
        x "authorRev"         = [Desc DocumentOrderByAuthor]
        x _                   = []

    docSearchingFromParams :: ListParams -> [DocumentFilter]
    docSearchingFromParams params =
      case listParamsSearching params of
        "" -> []
        x -> map DocumentFilterByString $ take 5 (splitWs x)

    docsPageSize :: Int
    docsPageSize = 100


apiCallV1CheckAvailable :: Kontrakcja m => m Response
apiCallV1CheckAvailable = api $ do
  (user, _actor, _) <- getAPIUser APIDocCheck
  (mids :: Maybe [DocumentID]) <- readField "ids"
  when (isNothing mids) $ do
    throwIO . SomeKontraException $ serverError "No ids parameter was provided or it had wrong format"
  let ids = $fromJust mids
  when (length ids > 10000) $ do
    throwIO . SomeKontraException $ serverError "This request can't check more then 10000 documents"
  docids <- dbQuery $ GetDocumentsIDs [DocumentsVisibleToUser $ userid user] [DocumentFilterDeleted False,DocumentFilterByDocumentIDs ids] []
  Ok <$> (J.runJSONGenT $ J.value "ids" (show <$> docids))



apiCallV1History :: Kontrakcja m => DocumentID -> m Response
apiCallV1History did = logDocument did . api $ do
  (user, _actor, _) <- getAPIUser APIDocCheck
  ctx <- getContext
  modifyContext (\ctx' -> ctx' {ctxmaybeuser = Just user});
  mlang <- (join . (fmap langFromCode)) <$> getField "lang"
  switchLang $ fromMaybe (lang $ usersettings user) mlang
  res <- jsonDocumentEvidenceLog did
  modifyContext (\ctx' -> ctx' {ctxmaybeuser = ctxmaybeuser ctx});
  return res


-- | This handler downloads main file of document. This means sealed file for Closed documents.
--   or one with preprinted fields if not closed

apiCallV1DownloadMainFile :: Kontrakcja m => DocumentID -> String -> m Response
apiCallV1DownloadMainFile did _nameForBrowser = logDocument did . api $ do

  (msid :: Maybe SignatoryLinkID) <- readField "signatorylinkid"
  (maccesstoken :: Maybe MagicHash) <- readField "accesstoken"
  mmh <- maybe (return Nothing) (dbQuery . GetDocumentSessionToken) msid

  doc <- do
           case (msid, mmh, maccesstoken) of
            (Just sid, Just mh, _) -> do
              (dbQuery $ GetDocumentByDocumentIDSignatoryLinkIDMagicHash did sid mh) `withDocumentM` do
                sl <- apiGuardJustM  (serverError "Signatory does not exist") $ getSigLinkFor sid <$> theDocument
                whenM (signatoryNeedsToIdentifyToView sl) $ do
                  unless (isAuthor sl) $ do
                    throwIO . SomeKontraException $ forbidden "Authorization to view is needed"
                theDocument
            (_, _, Just _) -> getDocByDocIDEx did maccesstoken
            _ ->  do
                  (user, _actor, external) <- getAPIUser APIDocCheck
                  if (external)
                    then do
                      ctx <- getContext
                      modifyContext (\ctx' -> ctx' {ctxmaybeuser = Just user});
                      res <- getDocByDocID did
                      modifyContext (\ctx' -> ctx' {ctxmaybeuser = ctxmaybeuser ctx});
                      return res;
                    else getDocByDocID did

  content <- case documentstatus doc of
                Closed -> do
                  when (documentsealstatus doc == Just Missing) $ do
                    now <- currentTime
                    -- Give Guardtime signing a few seconds to complete before we respond
                    when (diffUTCTime now (documentmtime doc) < 8) $ do
                      logInfo "Waiting for Guardtime signing" $ object [
                          "document_last_modified_ago" .= show (diffUTCTime now $ documentmtime doc)
                        ]
                      throwIO $ SomeKontraException $ noAvailableYet "Digitally sealed document not ready"
                  file <- apiGuardJustM (noAvailableYet "Not ready, please try later") $ fileFromMainFile (documentsealedfile doc)
                  getFileIDContents $ fileid file
                _ -> do
                  sourceFile <- apiGuardJustM  (serverError "No file") $ fileFromMainFile $ documentfile doc
                  apiGuardL  (serverError "Can't get file content")  $ DocSeal.presealDocumentFile doc sourceFile
  return $ respondWithPDF False content

apiCallV1DownloadFile :: Kontrakcja m => DocumentID -> FileID -> String -> m Response
apiCallV1DownloadFile did fileid nameForBrowser = logDocumentAndFile did fileid . api $ do
  (msid :: Maybe SignatoryLinkID) <- readField "signatorylinkid"
  (maccesstoken :: Maybe MagicHash) <- readField "accesstoken"
  mmh <- maybe (return Nothing) (dbQuery . GetDocumentSessionToken) msid
  doc <- do
           case (msid, mmh, maccesstoken) of
            (Just sid, Just mh, _) -> do
              (dbQuery $ GetDocumentByDocumentIDSignatoryLinkIDMagicHash did sid mh) `withDocumentM` do
                sl <- apiGuardJustM  (serverError "Signatory does not exist") $ getSigLinkFor sid <$> theDocument
                whenM (signatoryNeedsToIdentifyToView sl) $ do
                  unless (isAuthor sl) $ do
                    throwIO . SomeKontraException $ forbidden "Authorization to view is needed"
                theDocument
            (_, _, Just _accesstoken) -> getDocByDocIDEx did maccesstoken
            _ ->  do
                  (user, _actor, external) <- getAPIUser APIDocCheck
                  if (external)
                    then do
                      ctx <- getContext
                      modifyContext (\ctx' -> ctx' {ctxmaybeuser = Just user});
                      res <- getDocByDocID did
                      modifyContext (\ctx' -> ctx' {ctxmaybeuser = ctxmaybeuser ctx});
                      return res;
                    else getDocByDocID did
  let allfiles = maybeToList (mainfileid <$> documentfile doc) ++ maybeToList (mainfileid <$> documentsealedfile doc) ++
                      (authorattachmentfileid <$> documentauthorattachments doc) ++
                      (catMaybes $ map signatoryattachmentfile $ concatMap signatoryattachments $ documentsignatorylinks doc)
  if (all (/= fileid) allfiles)
     then throwIO . SomeKontraException $ forbidden "Access to file is forbiden."
     else do
        content <- getFileIDContents fileid
        let res = Response 200 Map.empty nullRsFlags (BSL.fromChunks [content]) Nothing
            ct = if (".pdf" `isSuffixOf` (map toLower nameForBrowser))
                    then  "application/pdf"
                    else if (".png" `isSuffixOf` (map toLower nameForBrowser))
                      then "image/png"
                      else if (".jpg" `isSuffixOf` (map toLower nameForBrowser))
                        then "image/jpeg"
                        else "application/octet-stream"
            res2 = setHeaderBS (BS.fromString "Content-Type") (BS.fromString ct) res
        return res2

apiCallV1ExtractTexts :: Kontrakcja m => DocumentID -> FileID -> m Response
apiCallV1ExtractTexts did fileid = logDocumentAndFile did fileid . api $ do
  (user, _actor , _) <- getAPIUser APIDocCreate
  withDocumentID did $ do
    unlessM (isPreparation <$> theDocument) $ do
      throwIO . SomeKontraException $ serverError "Can't extract texts from documents that are not in preparation"
    auid <- apiGuardJustM (serverError "No author found") $ ((maybesignatory =<<) . getAuthorSigLink) <$> theDocument
    when (not $ (auid == userid user)) $ do
      throwIO . SomeKontraException $ serverError "Permission problem. Not an author."


    jsons <- apiGuardL (badInput "The MIME part 'json' must exist and must be a JSON.") $ getDataFn' (look "json")
    json <- apiGuard (badInput "The MIME part 'json' must be a valid JSON.") $ case decode jsons of
                                                                                 J.Ok js -> Just js
                                                                                 _ -> Nothing
    doc <- theDocument
    when (Just fileid /= (mainfileid <$> documentfile doc)) $ do
      throwIO . SomeKontraException $ serverError "Requested file does not belong to the document"

    content <- getFileIDContents fileid
    runJavaTextExtract json content


{-

Java scrivepdftools extract-text expect as input json in the following format:

{ "rects": [ { "rect": [0,0,1,1],   // rectangle to extract text from, normalized to 0,0-1,1
               "page": 1},          // page number to extract from, starting from 1
             { "rect": [0,0,0.2,0.2],
               "page": 7 }]}

as output it will add keys to the json on the input:
{ "rects": [ { "rect": [0,0,1,1],   // rectangle to extract text from, normalized to 0,0-1,1
               "page": 1,           // page number to extract from, starting from 1
               "lines": [ "first line of extracted text",
                          "second line of extracted text" ]
             { "rect": [0,0,0.2,0.2],
               // no lines here as document has less than 7 pages
               "page": 7 }]}

java tool tries to preserve lines of text that were give in
pdf. Whitespace is normalized: no whitespec at the beginning or the
end, single space between words, newlines, tabs changed to
spaces. Note that whitespace in PDF is not reliable as sometimes
letters are just spread out visually but do not contain whitespace
character between them. When matching you should probably just run the
words together to stay on the safe side.

-}
runJavaTextExtract :: (Monad m,Kontrakcja m) => JSValue -> BS.ByteString -> m (Ok JSValue)
runJavaTextExtract json content = do
  withSystemTempDirectory' ("extract-texts-") $ \tmppath -> do
    let tmpin = tmppath ++ "/input.pdf"
    let specpath = tmppath ++ "/sealspec.json"

    let (rects :: Maybe JSValue) = fromJSValueField "rects" json
    let config = J.runJSONGen $ do
                   J.value "rects" rects

    liftIO $ BS.writeFile tmpin content
    liftIO $ BS.writeFile specpath (BS.fromString $ show $ J.pp_value (J.toJSValue config))
    (code,_stdout,stderr) <- liftIO $ do
      readProcessWithExitCode' "java" ["-jar", "scrivepdftools/scrivepdftools.jar", "extract-texts", specpath, tmpin] (BSL.empty)
    case code of
      ExitSuccess -> do
          (jsonresult :: JSValue) <- apiGuard (serverError "Backend did not return json.") $
                                        case decode (BSL.toString _stdout) of
                                          J.Ok js -> Just js
                                          _ -> Nothing
          let (rectsresult :: Maybe JSValue) = fromJSValueField "rects" jsonresult
          let censoredresult = J.runJSONGen $ do
                   J.value "rects" rectsresult
          return $ Ok censoredresult
      ExitFailure _ -> do
          logAttention "Extract texts failed" $ object [
              "configuration" .= jsonToAeson json
            , "stderr" `equalsExternalBSL` stderr
            ]
          apiGuardL (serverError "Extract texts failed on PDF") (return Nothing)

-- this one must be standard post with post params because it needs to
-- be posted from a browser form
-- Change main file, file stored in input "file" OR templateid stored in "template"
apiCallV1ChangeMainFile :: Kontrakcja m => DocumentID -> m Response
apiCallV1ChangeMainFile docid = logDocument docid . api $ do
  (user, actor, _) <- getAPIUser APIDocCreate
  checkObjectVersionIfProvided docid
  withDocumentID docid $ do
    auid <- apiGuardJustM (serverError "No author found") $ ((maybesignatory =<<) . getAuthorSigLink) <$> theDocument
    unlessM (isPreparation <$> theDocument) $ do
      throwIO . SomeKontraException $ (serverError "Document is not a draft or template")
    when (not $ (auid == userid user)) $ do
          throwIO . SomeKontraException $ serverError "Permission problem. Not an author."

    moldfileid <- fmap mainfileid <$> documentfile  <$> theDocument
    fileinput <- getDataFn' (lookInput "file")

    mft <- case fileinput of
      Nothing -> return Nothing
      Just (Input _ Nothing _) -> throwIO . SomeKontraException $ badInput "Missing file"
      Just (Input contentspec (Just filename') _contentType) -> do
        let filename = takeBaseName filename' ++ ".pdf"
        let mformat = getFileFormatForConversion filename'
        content1' <- case contentspec of
          Left filepath -> liftIO $ BS.readFile filepath
          Right content -> return (BS.concat (BSL.toChunks content))

        -- This is some kind of Salesforce hack that was supposed to be
        -- dropped with Happstack 7.0.4. It seems to be used till now
        -- for example by Avis.
        let content' = either (const content1') id (B64.decode content1')

        content'' <- case mformat of
          Nothing -> return content'
          Just format -> do
            ctx <- getContext
            eres <- convertToPDF (ctxlivedocxconf ctx) content' format
            case eres of
              Left (LiveDocxIOError e) -> throwIO . SomeKontraException $ serverError $ show e
              Left (LiveDocxSoapError s)-> throwIO . SomeKontraException $ serverError s
              Right res -> return $ res
        pdfcontent <- apiGuardL (badInput "The PDF is invalid.") $ preCheckPDF content''
        fileid' <- dbUpdate $ NewFile filename pdfcontent
        return $ Just (fileid', takeBaseName filename)

    case mft of
      Just (fileid,filename) -> do
        dbUpdate $ AttachFile fileid actor
        apiGuardL' $ dbUpdate $ SetDocumentTitle filename actor
        case moldfileid of
          Just oldfileid -> recalcuateAnchoredFieldPlacements oldfileid fileid
          Nothing -> return ()
      Nothing -> dbUpdate $ DetachFile actor
    Accepted <$> (documentJSONV1 (Just user) True True Nothing =<< theDocument)


apiCallV1SendSMSPinCode :: Kontrakcja m => DocumentID -> SignatoryLinkID ->  m Response
apiCallV1SendSMSPinCode did slid = logDocumentAndSignatory did slid . api $ do
  mh <- apiGuardL (serverError "No document found")  $ dbQuery $ GetDocumentSessionToken slid
  (dbQuery $ GetDocumentByDocumentIDSignatoryLinkIDMagicHash did slid mh) `withDocumentM` do
    sl <- apiGuardJustM  (serverError "No document found") $ getSigLinkFor slid <$> theDocument
    whenM (not . isPending <$> theDocument) $ do
       throwIO . SomeKontraException $ serverError "SMS pin code can't be sent to document that is not pending"
    when (SMSPinAuthenticationToSign /= signatorylinkauthenticationtosignmethod sl) $ do
       throwIO . SomeKontraException $ serverError "SMS pin code can't be sent to this signatory"
    phone <- apiGuardJustM (badInput "Phone number is no valid.") $ getOptionalField  asValidPhone "phone"
    pin <- dbQuery $ GetSignatoryPin slid phone
    sendPinCode sl phone pin
    Ok <$> (J.runJSONGenT $ J.value "sent" True)

apiCallV1GetBrandingForSignView :: Kontrakcja m => DocumentID -> SignatoryLinkID ->  m Response
apiCallV1GetBrandingForSignView did slid = logDocumentAndSignatory did slid . api $ do
  magichash <- apiGuardL (serverError "No document found")  $ dbQuery $ GetDocumentSessionToken slid
  doc <- dbQuery $ GetDocumentByDocumentID did
  sl <- apiGuardJustM  (serverError "No document found") $ return $ getMaybeSignatoryLink (doc,slid)
  when (signatorymagichash sl /= magichash) $ throwIO . SomeKontraException $ serverError "No document found"
  authorid <- apiGuardL (serverError "Document problem | No author") $ return $ getAuthorSigLink doc >>= maybesignatory
  user <- apiGuardL (serverError "Document problem | No author in DB") $ dbQuery $ GetUserByIDIncludeDeleted authorid
  company <- getCompanyForUser user
  Ok <$> (J.runJSONGenT $ documentSignviewBrandingJSON user company doc)

-- Signatory Attachments handling
apiCallV1SetSignatoryAttachment :: Kontrakcja m => DocumentID -> SignatoryLinkID -> String -> m Response
apiCallV1SetSignatoryAttachment did sid aname = logDocumentAndSignatory did sid . api $ do
  checkObjectVersionIfProvided did
  logInfo "Setting signatory attachments for signatory" $ object [
      "name" .= aname
    ]
  (mh,mu) <- getMagicHashAndUserForSignatoryAction did sid
  logInfo_ "We are authorized to set signatory attachment"
  -- We check permission here - because we are able to get a valid magichash here
  dbQuery (GetDocumentByDocumentIDSignatoryLinkIDMagicHash did sid mh) `withDocumentM` do
    unlessM (isPending <$> theDocument) $ do
            throwIO . SomeKontraException $ (badInput "Document is not pending")
    sl  <- apiGuard (badInput "There is no signatory by that id.") =<< getSigLinkFor sid <$> theDocument
    sigattach <- apiGuard (badInput "The attachment with that name does not exist for the signatory.") =<< getSignatoryAttachment sid aname <$> theDocument
    filedata <- getDataFn' (lookInput "file")
    mfileid <- case filedata of
      (Just (Input contentspec (Just filename) _contentType)) ->  Just <$>  do
                content1 <- case contentspec of
                  Left filepath -> liftIO $ BSL.readFile filepath
                  Right content -> return content
                content <- if (".pdf" `isSuffixOf` (map toLower filename))
                  then apiGuardL (badInput "The PDF was invalid.") $ preCheckPDF (BSL.toStrict content1)
                  else if (".png" `isSuffixOf` (map toLower filename) || ".jpg" `isSuffixOf` (map toLower filename))
                    then return $ Binary $ BSL.toStrict content1
                    else throwIO . SomeKontraException $ badInput "Only pdf files or images can be attached."
                (dbUpdate $ NewFile (dropFilePathFromWindows filename) content)
      _ -> return Nothing
    ctx <- getContext
    case mfileid of
      Just fileid -> (dbUpdate . SaveSigAttachment sid sigattach fileid =<< signatoryActor ctx sl)
                       `catchKontra` (\(DBBaseLineConditionIsFalse _) -> throwIO . SomeKontraException $ conflictError $ "Inconsistent state - attachment is already set")
      Nothing -> dbUpdate . DeleteSigAttachment sid sigattach =<< signatoryActor ctx sl

    Accepted <$> (documentJSONV1 mu True False (Just sl) =<< theDocument)

checkObjectVersionIfProvided :: Kontrakcja m => DocumentID -> m ()
checkObjectVersionIfProvided did = do
    mov <- readField "objectversion"
    case mov of
        Just ov -> dbQuery $ CheckDocumentObjectVersionIs did ov
        Nothing -> return ()
  `catchKontra` (\DocumentObjectVersionDoesNotMatch {} -> throwIO . SomeKontraException $ conflictError $ "Document object version does not match")

checkObjectVersionIfProvidedAndThrowError ::  (Kontrakcja m) => DocumentID -> APIError -> m ()
checkObjectVersionIfProvidedAndThrowError did err = do
    mov <- readField "objectversion"
    case mov of
        Just ov -> (dbQuery $ CheckDocumentObjectVersionIs did ov)
                      `catchKontra` (\DocumentObjectVersionDoesNotMatch {} -> throwIO . SomeKontraException $ conflictError $ "Document object version does not match")
        Nothing -> return ()
    throwIO . SomeKontraException $ err


-- Utils
guardAuthorOrAuthorsAdmin :: (Kontrakcja m,DocumentMonad m) => User -> String -> m ()
guardAuthorOrAuthorsAdmin user forbidenMessage = do
  docUserID <- apiGuardJustM (serverError "No author found") $ ((maybesignatory =<<) . getAuthorSigLink) <$> theDocument
  docUser   <- apiGuardJustM (serverError "No user found for author") $ dbQuery $ GetUserByIDIncludeDeleted docUserID
  let hasPermission = (docUserID == userid user) ||
                          ((usercompany docUser == usercompany user)
                            && (useriscompanyadmin user))
  when (not hasPermission) $
    throwIO . SomeKontraException $ forbidden forbidenMessage

getMagicHashAndUserForSignatoryAction :: (Kontrakcja m) =>  DocumentID -> SignatoryLinkID -> m (MagicHash,Maybe User)
getMagicHashAndUserForSignatoryAction did sid = do
    mh' <- dbQuery $ GetDocumentSessionToken sid
    case mh' of
      Just mh'' ->  return (mh'',Nothing)
      Nothing -> do
        (user, _ , _) <- getAPIUser APIPersonal
        logInfo "Logging user" $ object [
            "user" .= show user
          ]
        mh'' <- getMagicHashForDocumentSignatoryWithUser  did sid user
        case mh'' of
          Nothing -> throwIO . SomeKontraException $ serverError "Can't perform this action. Not authorized."
          Just mh''' -> return (mh''',Just $ user)

-- Helper type that represents ~field value, but without file reference - and only with file content. Used only locally.
data FieldTmpValue = StringFTV String
  | BoolFTV Bool
  | FileFTV BS.ByteString
    deriving (Eq, Ord, Show)

getValidPin :: (Kontrakcja m, DocumentMonad m) => SignatoryLinkID -> [(FieldIdentity, FieldTmpValue)] -> m (Maybe String)
getValidPin slid fields = do
  pin <- apiGuardJustM (badInput "Pin not provided or invalid.") $ getField "pin"
  phone <- case (lookup MobileFI fields) of
    Just (StringFTV v) -> return v
    _ ->  getMobile <$> $fromJust . getSigLinkFor slid <$> theDocument
  pin' <- dbQuery $ GetSignatoryPin slid phone
  if (pin == pin')
    then return $ Just pin
    else return $ Nothing

getFieldForSigning ::(Kontrakcja m) => m [(FieldIdentity, FieldTmpValue)]
getFieldForSigning = do
  eFieldsJSON <- getFieldJSON "fields"
  case eFieldsJSON of
    Nothing -> throwIO . SomeKontraException $ serverError "No fields description provided or fields description is not a valid JSON array"
    Just fieldsJSON -> do
      let mvalues = flip ($) fieldsJSON $ fromJSValueCustomMany $ do
            mfi <- fromJSValue
            mval <- fromJSValueField "value"
            return $ case (mfi, mval) of
              -- omg, this special case for empty value is such bullshit.
              (Just fi@(CheckboxFI _), Just "")  -> Just (fi, BoolFTV $ False)
              (Just fi@(CheckboxFI _), Just _ )  -> Just (fi, BoolFTV $ True)
              (Just fi@(SignatureFI _), Just "")  -> Just (fi, FileFTV "")
              (Just fi@(SignatureFI _), Just val) -> case (snd <$> RFC2397.decode (BS.pack val)) of
                Just bv -> Just (fi, FileFTV bv)
                _ -> Nothing
              (Just fi, Just val) -> Just (fi, StringFTV val)
              _ -> Nothing
      case mvalues of
        Nothing -> throwIO . SomeKontraException $ serverError "Fields description json has invalid format"
        Just values -> return values


fieldsToFieldsWithFiles :: (Kontrakcja m)
                           => [(FieldIdentity,FieldTmpValue)]
                           -> m ([(FieldIdentity,FieldValue)],[(FileID,BS.ByteString)])
fieldsToFieldsWithFiles [] = return ([],[])
fieldsToFieldsWithFiles (field:fields) = do
  (changeFields,files') <- fieldsToFieldsWithFiles fields
  case field of
    (fi,StringFTV s) -> return ((fi,StringFV s):changeFields,files')
    (fi,BoolFTV b)   -> return ((fi,BoolFV b):changeFields,files')
    (fi,FileFTV bs)  -> if (BS.null bs)
                          then return $ ((fi,FileFV Nothing):changeFields,files')
                          else do
                            fileid <- dbUpdate $ NewFile "signature.png" (Binary bs)
                            return $ ((fi,FileFV (Just fileid)):changeFields,(fileid,bs):files')
