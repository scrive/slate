module Doc.API.V2.Calls.DocumentGetCalls (
  docApiV2Available
, docApiV2List
, docApiV2Get
, docApiV2History
, docApiV2EvidenceAttachments
, docApiV2FilesMain
, docApiV2FilesGet
, docApiV2Texts
) where

import KontraPrelude
import Happstack.Server.Types
import Doc.Model.Update
import File.Model

import Doc.DocStateData
import API.V2
import Doc.API.V2.JSONDocument
import Doc.DocumentID
import Kontra
import Doc.DocumentMonad
import Data.Unjson
import Doc.DocInfo
import DB
import qualified Data.Map as Map hiding (map)
import Doc.API.V2.DocumentAccess
import Util.Actor
import Util.SignatoryLinkUtils
import OAuth.Model
import Doc.DocUtils
import User.Model
import Doc.Model
import Doc.API.V2.Guards
import Doc.API.V2.JSONList
import Doc.API.V2.Parameters

docApiV2Available :: Kontrakcja m => m Response
docApiV2Available = $undefined -- TODO implement

docApiV2List :: Kontrakcja m => m Response
docApiV2List = api $ do
  (user, _) <- getAPIUserWithPad APIDocCheck
  offset   <- apiV2Parameter' (ApiV2ParameterInt  "offset"  (OptionalWithDefault 0))
  maxcount <- apiV2Parameter' (ApiV2ParameterInt  "max"     (OptionalWithDefault 100))
  filters  <- apiV2Parameter' (ApiV2ParameterJSON "filter"  (OptionalWithDefault []) unjsonDef)
  sorting  <- apiV2Parameter' (ApiV2ParameterJSON "sorting" (OptionalWithDefault []) unjsonDef)
  let documentFilters = (DocumentFilterUnsavedDraft False):(join $ toDocumentFilter (userid user) <$> filters)
  let documentSorting = (toDocumentSorting <$> sorting)
  (allDocsCount, allDocs) <- dbQuery $ GetDocumentsWithSoftLimit [DocumentsVisibleToUser $ userid user] documentFilters documentSorting (offset,1000,maxcount)
  return $ Ok $ Response 200 Map.empty nullRsFlags (listToJSONBS (allDocsCount,(\d -> (documentAccessForUser user d,d)) <$> allDocs)) Nothing

docApiV2Get :: Kontrakcja m => DocumentID -> m Response
docApiV2Get did = api $ do
  ctx <- getContext
  -- If a 'signatory_id' parameter was given, we first check if the session
  -- has a matching and valid MagicHash for that SignatoryLinkID
  mSessionSignatory <- do
    mslid <- apiV2Parameter (ApiV2ParameterRead "signatory_id" Optional)
    case mslid of
      Nothing -> return Nothing
      Just slid -> getDocumentSignatoryMagicHash did slid
  (da, msl) <- case mSessionSignatory of
    Just sl -> do
      let slid = signatorylinkid sl
      return (DocumentAccess did $ SignatoryDocumentAccess slid, Just sl)
  -- If we didn't get a session *only* then we check normally and try to get
  -- a SignatoryLink too as we need to mark if they see the document
    Nothing -> withDocumentID did $ do
      (user,_) <- getAPIUser APIDocCheck
      doc <- theDocument
      let msiglink = getSigLinkFor user doc
      case msiglink of
        Just _ -> return ()
        Nothing -> guardThatUserIsAuthorOrCompanyAdminOrDocumentIsShared user
      return (documentAccessForUser user doc, msiglink)
  withDocumentID did $ do
    doc <- theDocument
    let canMarkSeen = not ((isTemplate || isPreparation || isClosed) doc)
    case (msl, canMarkSeen) of
      (Just sl, True) -> dbUpdate . MarkDocumentSeen (signatorylinkid sl) (signatorymagichash sl) =<< signatoryActor ctx sl
      _ -> return ()
    Ok <$> (\d -> (unjsonDocument $ da,d)) <$> theDocument

docApiV2History :: Kontrakcja m => DocumentID -> m Response
docApiV2History _did = $undefined -- TODO implement

docApiV2EvidenceAttachments :: Kontrakcja m => DocumentID -> m Response
docApiV2EvidenceAttachments _did = $undefined -- TODO implement

docApiV2FilesMain :: Kontrakcja m => DocumentID -> String -> m Response
docApiV2FilesMain _did _filename = $undefined -- TODO implement

docApiV2FilesGet :: Kontrakcja m => DocumentID -> FileID -> String -> m Response
docApiV2FilesGet _did _fid _filename = $undefined -- TODO implement

-------------------------------------------------------------------------------

docApiV2Texts :: Kontrakcja m => DocumentID -> FileID -> m Response
docApiV2Texts _did _fid = $undefined -- TODO implement
