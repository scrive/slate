module Archive.Control
       (
       handleDelete,
       handleReallyDelete,
       handleSendReminders,
       handleRestore,
       handleShare,
       handleCancel,
       handleZip,
       handleListCSV,
       showArchive
       )
       where

import Codec.Archive.Zip
import Control.Conditional (unlessM)
import Data.Char
import Data.Unjson (unjsonDef)
import Happstack.Server(Response)
import Log
import Text.JSON
import qualified Data.ByteString as BSS
import qualified Data.ByteString.Lazy as BSL
import qualified Data.Text as T
import qualified Text.JSON.Gen as J
import qualified Text.StringTemplates.Fields as F

import AppView
import Archive.View
import Company.Model (GetCompany(..))
import DB
import Doc.Action
import Doc.API.V1.DocumentToJSON (docForListCSVV1, docForListCSVHeaderV1)
import Doc.API.V2.JSON.List
import Doc.API.V2.Parameters (ApiV2Parameter(..), apiV2ParameterDefault)
import Doc.DocInfo (isPending)
import Doc.DocMails
import Doc.DocStateData
import Doc.DocumentID
import Doc.DocumentMonad (withDocument, theDocument, DocumentT)
import Doc.Model
import File.Storage as F
import InputValidation
import Kontra
import KontraLink
import KontraPrelude
import Log.Identifier
import User.Model
import User.Utils
import Util.Actor
import Util.CSVUtil
import Util.MonadUtils
import Util.SignatoryLinkUtils
import Util.ZipUtil

handleArchiveDocumentsAction :: forall m a. Kontrakcja m => String -> (User -> Document -> Bool) -> ((User, Actor) -> DocumentT m a) -> m [a]
handleArchiveDocumentsAction actionStr docPermission m = do
  ctx <- getContext
  user <- guardJust $ getContextUser ctx
  ids <- getCriticalField asValidDocIDList "documentids"
  docs <- dbQuery $ GetDocuments (DocumentsVisibleToUser $ userid user) [DocumentFilterByDocumentIDs ids] [] 100
  when (sort (map documentid docs) /= sort ids) $ failWithMsg user ids "Retrieved documents didn't match specified document ids"
  if all (docPermission user) docs
  then do
    let actor = userActor ctx user
    forM docs $ flip withDocument $ m (user, actor)
  else do
    failWithMsg user ids "User didn't have permission to do an action"
  where
    failWithMsg :: forall r. User -> [DocumentID] -> T.Text -> m r
    failWithMsg user ids msg = do
      logInfo msg $ object [
          "action" .= actionStr
        , identifier_ $ userid user
        , identifiers ids
        ]
      internalError

handleArchiveDocumentsAction' :: Kontrakcja m => String -> (User -> Document -> Bool) -> ((User, Actor) -> DocumentT m a) -> m JSValue
handleArchiveDocumentsAction' actionStr docPermission m = do
  _ <- handleArchiveDocumentsAction actionStr docPermission m
  J.runJSONGenT (return ())

handleDelete :: Kontrakcja m => m JSValue
handleDelete = do
  handleArchiveDocumentsAction' "cancel/reject documents" isDocumentVisibleToUser $ \(user, actor) -> do
        doc <- theDocument
        when (isPending doc) $
           if isAuthorOrAuthorsAdmin user doc
           then do
             dbUpdate $ CancelDocument actor
             postDocumentCanceledChange =<< theDocument
           else do
             -- user must be a regular signatory
             let Just (sl@SignatoryLink{signatorylinkid}) = getSigLinkFor user doc
             ctx <- getContext
             sl_actor <- signatoryActor ctx sl
             dbUpdate $ RejectDocument signatorylinkid  Nothing sl_actor
             theDocument >>= postDocumentRejectedChange signatorylinkid Nothing
        dbUpdate $ ArchiveDocument (userid user) actor

handleReallyDelete :: Kontrakcja m => m JSValue
handleReallyDelete = do
  handleArchiveDocumentsAction' "really delete documents" isDocumentVisibleToUser $ \(user, actor) -> do
    dbUpdate $ ReallyDeleteDocument (userid user) actor

handleSendReminders :: Kontrakcja m => m JSValue
handleSendReminders = handleArchiveDocumentsAction' "send reminders" isAuthorOrAuthorsAdmin $ \(_, actor) -> do
  remindedsiglinks <- sendAllReminderEmailsExceptAuthor actor False
  when (null remindedsiglinks) internalError

handleCancel :: Kontrakcja m =>  m JSValue
handleCancel = handleArchiveDocumentsAction' "cancel documents" isAuthorOrAuthorsAdmin $ \(_, actor) -> do
  unlessM (isPending <$> theDocument) internalError
  dbUpdate $ CancelDocument actor
  postDocumentCanceledChange =<< theDocument

handleRestore :: Kontrakcja m => m JSValue
handleRestore = handleArchiveDocumentsAction' "restore documents" isDocumentVisibleToUser $ \(user, actor) -> dbUpdate $ RestoreArchivedDocument user actor

handleShare :: Kontrakcja m => m JSValue
handleShare = handleArchiveDocumentsAction' "share documents" isAuthorOrAuthorsAdmin $ const $ do
  doc <- theDocument
  dbUpdate $ SetDocumentSharing [documentid doc] True

handleZip :: Kontrakcja m => m ZipArchive
handleZip = do
  logInfo_ "Downloading zip list"
  mentries <- handleArchiveDocumentsAction "download zipped documents" isDocumentVisibleToUser $ const $ do
               docToEntry =<< theDocument
  return $ ZipArchive "selectedfiles.zip" $ foldr addEntryToArchive emptyArchive $ catMaybes $ mentries


-- Fetch a csv file for documents from archive. It's not API call for V2 - just internal functionality used in archive.
-- It is still a part of list API call for V1 and this is why some V1 modules are imported.
-- It uses same format for sorting and filtering as current API list call and this is why some V2 modules are imported
handleListCSV :: Kontrakcja m => m CSV
handleListCSV= do
  logInfo_ "Downloading CSV list"
  ctx <- getContext
  user <- guardJust $ getContextUser ctx
  filters <- apiV2ParameterDefault []  (ApiV2ParameterJSON "filter" unjsonDef)
  sorting <- apiV2ParameterDefault []  (ApiV2ParameterJSON "sorting" unjsonDef)
  let documentFilters = (DocumentFilterUnsavedDraft False):(join $ toDocumentFilter (userid user) <$> filters)
  let documentSorting = (toDocumentSorting <$> sorting)
  allDocs <- dbQuery $ GetDocuments (DocumentsVisibleToUser $ userid user) documentFilters documentSorting 1000
  let docsCSVs = concatMap docForListCSVV1 allDocs
  return $ CSV { csvFilename = "documents.csv"
               , csvHeader = docForListCSVHeaderV1
               , csvContent = docsCSVs
               }

-- | Main view of the archive
showArchive :: Kontrakcja m => m (Either KontraLink Response)
showArchive = checkUserTOSGet $ do
    tostime <- guardJustM $ join <$> fmap userhasacceptedtermsofservice <$> ctxmaybeuser <$> getContext
    user    <- guardJustM $ ctxmaybeuser <$> getContext
    mcompany <- dbQuery $ GetCompany (usercompany user)
    pb <-  pageArchive user mcompany tostime
    renderFromBodyWithFields pb (F.value "archive" True)

-- Zip utils

docToEntry ::  Kontrakcja m => Document -> m (Maybe Entry)
docToEntry doc = do
      let name = filter ((/= ' ')) $ filter (isAscii) $ (documenttitle doc) ++ "_" ++ (show $ documentid doc) ++".pdf"
      case mainfileid <$> documentsealedfile doc `mplus` documentfile doc of
        Just fid -> do
            content <- getFileIDContents fid
            return $ Just $ toEntry name 0 $ BSL.pack $ BSS.unpack content
        Nothing -> return Nothing
