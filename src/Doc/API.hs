module Doc.API (documentAPI) where

import Happstack.StaticRouting
import Text.JSON
import KontraMonad
import Util.JSON
import Happstack.Server.Types
import Routing
import Doc.DocStateQuery
import Doc.DocStateData
import Doc.Model
import Doc.JSON
import Control.Applicative
import Control.Logic
import Control.Monad.Trans
import Misc
import Data.Maybe
import qualified Data.ByteString.UTF8 as BS hiding (length)
import qualified Data.ByteString.Lazy as BSL
import Util.Actor
import Util.SignatoryLinkUtils
import Util.HasSomeUserInfo
import Happstack.Server.RqData
import Doc.DocStorage
import DB
import File.Model
import MagicHash (MagicHash)
import Kontra
import Doc.DocUtils
import User.Model
import Company.Model
import Happstack.Server.Monads
import API.Monad
import Control.Monad.Error
import qualified Log
import Stats.Control

documentAPI :: Route (KontraPlus Response)
documentAPI = choice [
  dir "api" $ dir "document" $ hPostNoXToken $ toK0 $ documentNew,

  -- /api/mainfile/{docid} ==> Change main file
  dir "api" $ dir "mainfile" $ hPostNoXToken $ toK1 $ documentChangeMainFile,

  dir "api" $ dir "document" $ hPostNoXToken $ toK6 $ documentUploadSignatoryAttachment,
  dir "api" $ dir "document" $ hDelete       $ toK6 $ documentDeleteSignatoryAttachment,
  dir "api" $ dir "document" $ hPostNoXToken $ toK2 $ documentChangeMetadata
  ]

-- this one must be standard post with post params because it needs to
-- be posted from a browser form
documentNew :: Kontrakcja m => m Response
documentNew = api $ do
  user <- getAPIUser
  mcompany <- case usercompany user of
    Nothing -> return Nothing
    Just cid -> do
      a <- apiGuardL $ dbQuery $ GetCompany cid
      return $ Just a
  
  doctypes <- apiGuardL' BadInput $ getDataFn' (look "type")
  
  doctypei <- apiGuard' BadInput $ maybeRead doctypes
  
  doctype <- apiGuard' BadInput $ toSafeEnumInt doctypei
  
  -- pdf exists  
  (Input contentspec (Just filename') _contentType) <- apiGuardL' BadInput $ getDataFn' (lookInput "file")
  
  let filename = basename filename'
      
  content1 <- case contentspec of
    Left filepath -> liftIO $ BSL.readFile filepath
    Right content -> return content
  
  -- we need to downgrade the PDF to 1.4 that has uncompressed structure
  -- we use gs to do that of course
  ctx <- getContext
  let now = ctxtime ctx
  
  let aa = authorActor now (ctxipnumber ctx) (userid user) (getEmail user)
  d1 <- apiGuardL $ dbUpdate $ NewDocument user mcompany filename doctype 1 aa
  
  content <- apiGuardL' BadInput $ liftIO $ preCheckPDF (ctxgscmd ctx) (concatChunks content1)
  file <- lift $ dbUpdate $ NewFile filename content

  d2 <- apiGuardL $ dbUpdate $ AttachFile (documentid d1) (fileid file) aa
  _ <- lift $ addDocumentCreateStatEvents d2 "web"
  return $ Created $ jsonDocumentForAuthor d2

-- this one must be standard post with post params because it needs to
-- be posted from a browser form
-- Change main file, file stored in input "file" OR templateid stored in "template"
documentChangeMainFile :: Kontrakcja m => DocumentID -> m Response
documentChangeMainFile docid = api $ do
  ctx <- getContext
  aa <- apiGuard' Forbidden $ mkAuthorActor ctx
  doc <- apiGuardL' Forbidden $ getDocByDocID docid
  apiGuard' Forbidden (isAuthor $ getAuthorSigLink doc)

  fileinput <- lift $ getDataFn' (lookInput "file")
  templateinput <- lift $ getDataFn' (look "template")

  fileid <- case (fileinput, templateinput) of
            (Just (Input contentspec (Just filename') _contentType), _) -> do
              content1 <- case contentspec of
                Left filepath -> liftIO $ BSL.readFile filepath
                Right content -> return content
                
              -- we need to downgrade the PDF to 1.4 that has uncompressed structure
              -- we use gs to do that of course
              content <- apiGuardL' BadInput $ liftIO $ preCheckPDF (ctxgscmd ctx) (concatChunks content1)
              let filename = basename filename'
      
              fileid <$> (dbUpdate $ NewFile filename content)
            (_, Just templateids) -> do
              templateid <- apiGuard' BadInput $ maybeRead templateids
              temp <- apiGuardL $ getDocByDocID templateid
              apiGuard' BadInput $ listToMaybe $ documentfiles temp
            _ -> throwError BadInput
  
  _ <- apiGuardL $ dbUpdate $ AttachFile docid fileid aa
  return ()


documentChangeMetadata :: Kontrakcja m => DocumentID -> MetadataResource -> m Response
documentChangeMetadata docid _ = api $ do
  user <- getAPIUser  
  doc <- apiGuardL $ dbQuery $ GetDocumentByDocumentID docid
  
  asl <- apiGuard $ getAuthorSigLink doc
  
  apiGuard' Forbidden (Just (userid user) == maybesignatory asl)
    
  rq <- lift askRq
    
  bdy <- apiGuardL $ liftIO $ takeRequestBody rq
  let jstring = BS.toString $ concatChunks $ unBody bdy
  
  json <- apiGuard $ decode jstring
  ctx <- getContext
  let now = ctxtime ctx
  let actor = authorActor now (ctxipnumber ctx) (userid user) (getEmail user)
  d <- case jsget "title" json of
    Left _ -> return doc
    Right (JSString s) ->
      apiGuardL $ dbUpdate $ SetDocumentTitle docid (fromJSString s) actor
    Right _ -> throwError BadInput
      
  return $ jsonDocumentMetadata d

--documentView :: (Kontrakcja m) => DocumentID -> m Response
--documentView (_ :: DocumentID) = api $  undefined


data SignatoryResource = SignatoryResource
instance FromReqURI SignatoryResource where
    fromReqURI s = Just SignatoryResource <| s == "signatory" |> Nothing

data AttachmentResource = AttachmentResource
instance FromReqURI AttachmentResource where
    fromReqURI s = Just AttachmentResource <| s == "attachment" |> Nothing
    
data FileResource = FileResource
instance FromReqURI FileResource where
    fromReqURI s = Just FileResource <| s == "file" |> Nothing

data MetadataResource = MetadataResource
instance FromReqURI MetadataResource where
    fromReqURI s = Just MetadataResource <| s == "metadata" |> Nothing
 
getSigLinkID :: Kontrakcja m => APIMonad m (SignatoryLinkID, MagicHash)
getSigLinkID = do
  msignatorylink <- lift $ readField "signatorylinkid"
  mmagichash <- lift $ readField "magichash"
  case (msignatorylink, mmagichash) of
       (Just sl, Just mh) -> return (sl,mh)
       _ -> throwError BadInput
  
documentUploadSignatoryAttachment :: Kontrakcja m => DocumentID -> SignatoryResource -> SignatoryLinkID -> AttachmentResource -> String -> FileResource -> m Response
documentUploadSignatoryAttachment did _ sid _ aname _ = api $ do
  Log.debug $ "sigattachment ajax"
  (slid, magichash) <- getSigLinkID
  doc <- apiGuardL $ getDocByDocIDSigLinkIDAndMagicHash did slid magichash
  sl  <- apiGuard $ getSigLinkFor doc sid
  let email = getEmail sl
  
  sigattach <- apiGuard' Forbidden $ getSignatoryAttachment doc slid aname
  
  -- attachment must have no file
  apiGuard' ActionNotAvailable (isNothing $ signatoryattachmentfile sigattach)
  
  -- pdf exists in input param "file"
  (Input contentspec (Just filename) _contentType) <- apiGuardL' BadInput $ getDataFn' (lookInput "file")
  
  content1 <- case contentspec of
    Left filepath -> liftIO $ BSL.readFile filepath
    Right content -> return content
  
  -- we need to downgrade the PDF to 1.4 that has uncompressed structure
  -- we use gs to do that of course
  ctx <- getContext

  content <- apiGuardL' BadInput $ liftIO $ preCheckPDF (ctxgscmd ctx) (concatChunks content1)
  
  file <- lift $ dbUpdate $ NewFile (basename filename) content
  let actor = signatoryActor (ctxtime ctx) (ctxipnumber ctx) (maybesignatory sl) email slid
  d <- apiGuardL $ dbUpdate $ SaveSigAttachment (documentid doc) sid aname (fileid file) actor
  
  -- let's dig the attachment out again
  sigattach' <- apiGuard $ getSignatoryAttachment d sid aname
  
  return $ Created $ jsonSigAttachmentWithFile sigattach' (Just file)

documentDeleteSignatoryAttachment :: Kontrakcja m => DocumentID -> SignatoryResource -> SignatoryLinkID -> AttachmentResource -> String -> FileResource -> m Response
documentDeleteSignatoryAttachment did _ sid _ aname _ = api $ do
  Context{ctxtime, ctxipnumber} <- getContext
  (slid, magichash) <- getSigLinkID
  doc <- apiGuardL $ getDocByDocIDSigLinkIDAndMagicHash did slid magichash
  
  sl <- apiGuard $ getSigLinkFor doc sid
  let email = getEmail sl
      muid  = maybesignatory sl
  
  
  -- sigattachexists
  sigattach <- apiGuard $ getSignatoryAttachment doc slid aname

  -- attachment must have a file
  fileid <- apiGuard' ActionNotAvailable $ signatoryattachmentfile sigattach

  d <- apiGuardL $ dbUpdate $ DeleteSigAttachment (documentid doc) sid fileid
       (signatoryActor ctxtime ctxipnumber muid email sid)
  
  -- let's dig the attachment out again
  sigattach' <- apiGuard $ getSignatoryAttachment d sid aname
  
  return $ jsonSigAttachmentWithFile sigattach' Nothing

   
