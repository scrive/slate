module Archive.Control
       (
       handleDelete,
       handleSendReminders,
       handleRestore,
       handleShare,
       handleCancel,
       handleZip,
       showArchive,
       jsonDocumentsList
       )
       where

import Archive.View

import InputValidation
import KontraLink
import Kontra
import DB
import Doc.DocStateData
import Doc.Model
import User.Model
import User.Utils
import Util.MonadUtils

import Control.Applicative
import Util.SignatoryLinkUtils
import Util.Actor
import Text.JSON
import Util.CSVUtil
import ListUtil
import Happstack.Fields
import PadQueue.Model
import Data.Maybe
import Text.JSON.Gen as J
import Text.JSON.FromJSValue
import Doc.Action
import Doc.DocMails
import Doc.DocStateQuery
import Control.Monad
import Codec.Archive.Zip
import Util.ZipUtil
import qualified Data.ByteString.Lazy as BSL
import qualified Data.ByteString as BSS
import Data.Char
import File.Storage as F
import qualified Log as Log
import Control.Logic
import Control.Monad.Identity
import Text.JSON.String (runGetJSON)
import Doc.DocDraft()
import Data.String.Utils (splitWs)
import MinutesTime
import AppView
import Happstack.Server(Response)
import qualified Text.StringTemplates.Fields as F

handleDelete :: Kontrakcja m => m JSValue
handleDelete = do
    ctx@(Context { ctxmaybeuser = Just user }) <- getContext
    docids <- getCriticalField asValidDocIDList "documentids"
    let actor = userActor ctx user
    docs <- getDocsByDocIDs docids
    forM_ docs $ \doc -> do
              let usl = getSigLinkFor doc user
                  csl = (getAuthorSigLink $ documentsignatorylinks doc) <| (useriscompanyadmin user) |> Nothing
                  msl =  usl `mplus` csl
              when (isNothing msl) $ do
                Log.debug $ "User #" ++ show (userid user) ++ " has no rights to deleted document #" ++ show (documentid doc)
                internalError
              case (documentstatus doc) of
                  Pending -> if (isAuthor msl)
                                then do
                                   dbUpdate $ CancelDocument (documentid doc) actor
                                   doc' <- getDocByDocID (documentid doc)
                                   postDocumentCanceledChange doc'
                                else do
                                   dbUpdate $ RejectDocument (documentid doc) (signatorylinkid $ fromJust msl) Nothing actor
                                   doc' <- getDocByDocID (documentid doc)
                                   postDocumentRejectedChange doc' (signatorylinkid $ fromJust msl)
                  _ -> return ()
              dbUpdate $ ArchiveDocument (userid user) (documentid doc) actor

    J.runJSONGenT $ return ()



handleSendReminders :: Kontrakcja m => m JSValue
handleSendReminders = do
    ctx <- getContext
    ids <- getCriticalField asValidDocIDList "documentids"
    actor <- guardJustM $ fmap mkAuthorActor getContext
    remindedsiglinks <- fmap concat . sequence . map (\docid -> sendAllReminderEmailsExceptAuthor ctx actor docid) $ ids
    case (length remindedsiglinks) of
      0 -> internalError
      _ -> J.runJSONGenT $ return ()

handleCancel :: Kontrakcja m =>  m JSValue
handleCancel = do
  docids <- getCriticalField asValidDocIDList "documentids"
  forM_ docids $ \docid -> do
      doc <- getDocByDocID docid
      actor <- guardJustM $ mkAuthorActor <$> getContext
      if (documentstatus doc == Pending)
        then do
           dbUpdate $ CancelDocument (documentid doc) actor
           doc' <- getDocByDocID $ docid
           postDocumentCanceledChange doc'
        else internalError
  J.runJSONGenT $ return ()

handleRestore :: Kontrakcja m => m JSValue
handleRestore = do
  user <- guardJustM $ ctxmaybeuser <$> getContext
  actor <- guardJustM $ mkAuthorActor <$> getContext
  docids <- getCriticalField asValidDocIDList "documentids"
  mapM_ (\did -> dbUpdate $ RestoreArchivedDocument user did actor) docids
  J.runJSONGenT $ return ()

handleShare :: Kontrakcja m => m JSValue
handleShare =  do
    _ <- guardJustM $ ctxmaybeuser <$> getContext
    ids <- getCriticalField asValidDocIDList "documentids"
    _ <- dbUpdate $ SetDocumentSharing ids True
    J.runJSONGenT $ return ()

handleZip :: Kontrakcja m => m ZipArchive
handleZip = do
  Log.debug $ "Downloading zip list"
  docids <- take 100 <$> getCriticalField asValidDocIDList "documentids"
  mentries <- forM docids $ \did -> do
                Log.debug "Getting file for zip download"
                doc <- getDocByDocID did
                docToEntry doc
  return $ ZipArchive "selectedfiles.zip" $ foldr addEntryToArchive emptyArchive $ map fromJust $ filter isJust $ mentries
{- |
   Constructs a list of documents (Arkiv) to show to the user.
 -}
showArchive :: Kontrakcja m => m (Either KontraLink Response)
showArchive = checkUserTOSGet $ do
    tostime <- guardJustM $ join <$> fmap userhasacceptedtermsofservice <$> ctxmaybeuser <$> getContext
    user    <- guardJustM $ ctxmaybeuser <$> getContext
    pb <-  pageArchive user tostime
    renderFromBodyWithFields kontrakcja pb (F.value "archive" True)


jsonDocumentsList ::  Kontrakcja m => m (Either CSV JSValue)
jsonDocumentsList = do
  Log.debug $ "Long list " ++ (show $ map fromEnum [SCDraft,SCCancelled,SCRejected,SCTimedout,SCError,SCDeliveryProblem,SCSent,SCDelivered,SCRead,SCOpened,SCSigned])
  user@User{userid = uid} <- guardJustM $ ctxmaybeuser <$> getContext
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
                          _ -> ([DocumentsVisibleToUser uid],[DocumentFilterDeleted False, DocumentFilterUnsavedDraft False])
      filters2 = concatMap fltSpec (listParamsFilters params)
      fltSpec ("time", tostr) = case reads tostr of
                                    (((Just from',Just to'),""):_) -> [DocumentFilterByMonthYearFrom from',DocumentFilterByMonthYearTo to']
                                    (((Nothing ,Just to'),""):_) -> [DocumentFilterByMonthYearTo to']
                                    (((Just from',Nothing),""):_)   -> [DocumentFilterByMonthYearFrom from']
                                    _ -> []
      fltSpec ("mtime", tostr) = case parseMinutesTimeRealISO tostr of
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
                      Right js ->[DocumentFilterByTags $ join $ maybeToList $ runIdentity $ withJSValue js $ fromJSValueCustomMany $ fromJSValueM]
                      _ -> []
  let sorting    = docSortingFromParams params
      searching  = docSearchingFromParams params
      pagination2 = ((listParamsOffset params),(listParamsLimit params), Just docsPageSize)
      filters = filters1 ++ filters2 ++ tagsFilters ++ [DocumentFilterPurged False]

  padqueue <- dbQuery $ GetPadQueue $ userid user
  format <- getField "format"
  case format of
       Just "csv" -> do
          allDocs <- dbQuery $ GetDocuments domain (searching ++ filters) sorting (0,-1)
          let docsCSVs = concat $ zipWith docForListCSV  [1..] allDocs
          return $ Left $ CSV { csvFilename = "documents.csv"
                              , csvHeader = docForListCSVHeader
                              , csvContent = docsCSVs
                              }
       _ -> do
          (allDocsCount,allDocs) <- dbQuery $ GetDocuments2 True domain (searching ++ filters) sorting pagination2
          let docs = PagedList {  list       = allDocs
                                , params     = params
                                , pageSize   = docsPageSize
                                , listLength = allDocsCount
                                }
          docsJSONs <- mapM (docForListJSON user padqueue) $ list docs
          return $ Right $ runJSONGen $ do
              value "list" docsJSONs
              value "paging" $ pagingParamsJSON docs

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

-- Zip utils

docToEntry ::  Kontrakcja m => Document -> m (Maybe Entry)
docToEntry doc = do
      let name = filter ((/= ' ')) $ filter (isAscii) $ (documenttitle doc) ++ "_" ++ (show $ documentid doc) ++".pdf"
      case documentsealedfile doc `mplus` documentfile doc of
        Just fid -> do
            content <- getFileIDContents fid
            return $ Just $ toEntry name 0 $ BSL.pack $ BSS.unpack content
        Nothing -> return Nothing
