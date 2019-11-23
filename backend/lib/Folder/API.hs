module Folder.API (
    folderAPIRoutes
  , folderAPI
  , folderAPICreate
  , folderAPIDelete
  , folderAPIGet
  , folderAPIListDocs
  , folderAPIUpdate
) where

import Control.Monad.Base
import Control.Monad.Extra (unlessM)
import Data.Aeson
import Data.Time
import Data.Unjson
import Happstack.Server.Types
import Happstack.StaticRouting
import Log
import qualified Data.Text as T

import AccessControl.Model
import AccessControl.Types
import API.V2
import API.V2.Errors
import API.V2.Parameters
import API.V2.Utils
import DB
import Doc.API.V2.DocumentAccess
import Doc.API.V2.JSON.Document
import Doc.API.V2.JSON.List
import Doc.Model
import Folder.JSON
import Folder.Model
import Kontra
import Log.Identifier
import OAuth.Model
import Routing

folderAPIRoutes :: Route (Kontra Response)
folderAPIRoutes = dir "api" $ choice [dir "frontend" $ folderAPI, dir "v2" $ folderAPI]

folderAPI :: Route (Kontra Response)
folderAPI = dir "folders" $ choice
  [ hGet $ toK1 $ folderAPIGet
  , dir "create" . hPost . toK0 $ folderAPICreate
  , param . dir "update" . hPost . toK1 $ folderAPIUpdate
  , param . dir "delete" . hPost . toK1 $ folderAPIDelete
  , param . dir "list" . hGet . toK1 $ folderAPIListDocs
  ]

folderAPICreate :: Kontrakcja m => m Response
folderAPICreate = api $ do
  fdru  <- apiV2ParameterObligatory $ ApiV2ParameterAeson "folder"
  fdrIn <- case updateFolderWithFolderFromRequest defaultFolder fdru of
    Nothing            -> apiError $ requestFailed "Error parsing folder create object."
    Just folderUpdated -> return folderUpdated
  fid <- view #id <$> case fdrIn ^. #parentID of
    Nothing -> do
      -- guard against non-admins being able to create root folders
      unlessM checkAdminOrSales $ apiError insufficientPrivileges
      dbUpdate $ FolderCreate fdrIn
    Just parent_id -> do
      -- Check user has permissions to create child folder
      let acc = [mkAccPolicyItem (CreateA, FolderR, parent_id)]
      apiuser <- getAPIUserWithAPIPersonal
      apiAccessControlOrIsAdmin apiuser acc . dbUpdate $ FolderCreate fdrIn
  Ok . encodeFolderWithChildren <$> folderWithChildrenOrAPIError fid

folderAPIGet :: Kontrakcja m => FolderID -> m Response
folderAPIGet fid = api $ do
  let acc = mkAccPolicy [(ReadA, FolderR, fid)]
  user           <- getAPIUserWithAPIPersonal
  hasReadAccess  <- apiAccessControlCheck user acc
  isAdminOrSales <- checkAdminOrSales
  fdrwc          <- if (hasReadAccess || isAdminOrSales)
    then folderWithChildrenOrAPIError fid
    else do
      isSignatory <- isSignatoryOfOneOfDocuments
      if isSignatory
        then folderWithChildrenOrAPIError fid
        else apiError insufficientPrivileges
  return . Ok $ encodeFolderWithChildren fdrwc
  where
    isSignatoryOfOneOfDocuments :: Kontrakcja m => m Bool
    isSignatoryOfOneOfDocuments = do
      user      <- fst <$> getAPIUserWithAnyPrivileges
      documents <- dbQuery $ GetDocumentsIDs
        (DocumentsUserHasAnyLinkTo $ user ^. #id)
        [DocumentFilterDeleted False, DocumentFilterByFolderID fid]
        []
      return . (> 0) $ length documents

folderAPIUpdate :: Kontrakcja m => FolderID -> m Response
folderAPIUpdate fid = api $ do
  (dbQuery (FolderGet fid)) >>= \case
    -- must do manual existence checking since we haven't done access control checks yet
    Nothing    -> apiError insufficientPrivileges
    Just fdrDB -> do
      fdrfuin <- apiV2ParameterObligatory $ ApiV2ParameterAeson "folder"
      fdrNew  <- case updateFolderWithFolderFromRequest fdrDB fdrfuin of
        Nothing -> apiError $ requestFailed "Error parsing folder update object."
        Just folderUpdated -> return folderUpdated
      let mtoParentID   = fdrNew ^. #parentID
          mfromParentID = fdrDB ^. #parentID
      accParents <- if (mfromParentID == mtoParentID)
        -- child is remaining in same place. no special privileges needed
        then return []
        else case (mfromParentID, mtoParentID) of
          -- change parent
          (Just fromParentID, Just toParentID) ->
            return [(UpdateA, FolderR, toParentID), (UpdateA, FolderR, fromParentID)]
          -- change from being child to root
          (Just _, Nothing) -> do
            -- Only admin or sales can promote Folder to root
            unlessM checkAdminOrSales $ apiError insufficientPrivileges
            return []
          -- change from being root to child
          (Nothing, Just toParentID) -> return [(UpdateA, FolderR, toParentID)]
          -- root is remaining root. no special privileges needed
          _ -> return []
      let acc = mkAccPolicy $ [(UpdateA, FolderR, fid)] <> accParents
      apiuser <- getAPIUserWithAPIPersonal
      apiAccessControlOrIsAdmin apiuser acc $ do
        void . dbUpdate . FolderUpdate $ fdrNew
        Ok . encodeFolderWithChildren <$> folderWithChildrenOrAPIError fid

folderAPIDelete :: Kontrakcja m => FolderID -> m Response
folderAPIDelete fid = api $ do
  apiuser <- getAPIUserWithAPIPersonal
  apiAccessControlOrIsAdmin apiuser [mkAccPolicyItem (DeleteA, FolderR, fid)] $ do
    fdr <- folderOrAPIError fid
    let isRootFolder = isNothing $ fdr ^. #parentID
    when isRootFolder
      $
      -- cf. `userGroupApiV2Delete`
        apiError
      $ requestFailed "Root folders cannot be deleted."
    dbUpdate $ FolderDelete fid
    dbUpdate $ AccessControlDeleteRolesByFolder fid
    return
      .  Ok
      .  pairs
      $  ("id" .= show fid)
      <> ("resource" .= ("folder" :: T.Text))
      <> ("action" .= ("deleted" :: T.Text))

folderAPIListDocs :: Kontrakcja m => FolderID -> m Response
folderAPIListDocs fid = api $ do
  (user, _) <- getAPIUserWithPad APIDocCheck
  let acc = mkAccPolicy $ [(ReadA, FolderR, fid)]
  apiAccessControlOrIsAdmin user acc $ do
    offset   <- apiV2ParameterDefault 0 (ApiV2ParameterInt "offset")
    maxcount <- apiV2ParameterDefault 100 (ApiV2ParameterInt "max")
    sorting  <- apiV2ParameterDefault defaultDocumentAPISort
                                      (ApiV2ParameterJSON "sorting" unjsonDef)
    let documentSorting = (toDocumentSorting <$> sorting)
    logInfo "Fetching list of documents in the folder" $ object
      [ identifier $ user ^. #id
      , "offset" .= offset
      , "max_count" .= maxcount
      , "sorting" .= map show documentSorting
      ]
    startQueryTime          <- liftBase getCurrentTime
    (allDocsCount, allDocs) <- dbQuery $ GetDocumentsWithSoftLimit
      (DocumentsByFolderOnly fid)
      []
      documentSorting
      (offset, 1000, maxcount)
    finishQueryTime <- liftBase getCurrentTime
    logInfo "Fetching for folderAPIListDocs done" $ object
      [ "query_time"
          .= (realToFrac $ diffUTCTime finishQueryTime startQueryTime :: Double)
      ]
    let headers = mkHeaders [("Content-Type", "application/json; charset=UTF-8")]
        jsonbs  = listToJSONBS
          (allDocsCount, (\d -> (documentAccessForUser user d, d)) <$> allDocs)
    return . Ok $ Response 200 headers nullRsFlags jsonbs Nothing
