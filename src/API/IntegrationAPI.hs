{-# LANGUAGE CPP #-}
-----------------------------------------------------------------------------
-- |
-- Module      :  API.Integration
-- Maintainer  :  all
-- Stability   :  development
-- Portability :  portable
--
-- Integration API is advanced way to integrate with our service using mix of
-- request and iframes
-----------------------------------------------------------------------------
module API.IntegrationAPI (
    -- For main server we export only this
      integrationAPI
    -- For tests (and only for tests)
    , IntegrationAPIFunction
    , embeddDocumentFrame
    , createDocument
    , getDocuments
    , getDocument
    , setDocumentTag
    , removeDocument
    , getDaveDoc
    ) where

import Control.Monad.State
import Data.Functor
import Data.Maybe
import DB.Classes
import Doc.Model
import Doc.DocStateData
import Happstack.Server (Response, finishWith, askRq, rqUri, look, toResponseBS)
import Happstack.StaticRouting(Route, dir, choice)
import KontraLink
import MinutesTime
import Misc
import Session
import Kontra
import AppView
import qualified Data.ByteString as BS
import qualified Data.ByteString.UTF8 as BS
import InputValidation
import Text.JSON
import Control.Monad.Reader
import API.API
import Routing
import API.Service.Model
import API.APICommons
import Doc.DocUtils
import Company.Model
import User.Model
import Data.Foldable (fold)
import Crypto.RNG (CryptoRNG, randomBytes)
import Util.SignatoryLinkUtils
import Util.HasSomeCompanyInfo
import Util.HasSomeUserInfo
import Util.ServiceUtils
import Util.MonadUtils
import Templates.Templates
import Stats.Control
import File.Model
import Util.JSON
import Text.JSON.String
import qualified Data.ByteString.Lazy.UTF8 as BSL (fromString)
import Doc.SignatoryTMP
import qualified Log (integration)
import Doc.DocStorage
import User.History.Model

import EvidenceLog.Model

{- |
  Definition of integration API
-}

data IntegrationAPIContext = IntegrationAPIContext {ibody :: APIRequestBody , service :: Service}
type IntegrationAPIFunction m a = APIFunction m IntegrationAPIContext a

instance APIContext IntegrationAPIContext where
    apiContext  = do
        mservice <- integrationService
        mbody <- runGetJSON readJSObject <$> getFieldWithDefault "" "body"
        case (mservice, mbody)  of
             (Just service, Right body2) -> do
                Log.integration $ "API call from service:" ++ show (serviceid service)
                Log.integration $ "API call body is:" ++ (take 300 $ encode body2)
                return $ Right $ IntegrationAPIContext {ibody=body2,service=service}
             (Nothing,_) -> return $ Left $ (API_ERROR_LOGIN ,"Bad service/password")
             (_,Left s) -> return $ Left $ (API_ERROR_PARSING,"Parsing error: " ++ s)

instance JSONContainer IntegrationAPIContext where
    getJSON = ibody
    setJSON j iapic = iapic {ibody = j}

integrationService :: Kontrakcja m => m (Maybe Service)
integrationService = do
    sid <- getFieldUTFWithDefault BS.empty "service"
    mservice <- runDBQuery $ GetService $ ServiceID sid
    case mservice of
         Just service -> do
             passwd <- getFieldUTFWithDefault BS.empty "password"
             if (verifyPassword (servicepassword $ servicesettings service) passwd)
                then return $ Just service
                else return Nothing
         Nothing -> return Nothing

integrationAPI :: Route (Kontra Response)
integrationAPI = dir "integration" $ choice [
      dir "api" $
        choice
          [ apiCall "embed_document_frame" embeddDocumentFrame
          , apiCall "new_document" createDocument
          , apiCall "documents" getDocuments
          , apiCall "document" getDocument
          , apiCall "set_document_tag" setDocumentTag
          , apiCall "remove_document" removeDocument
          , apiUnknownCall
          ]
    , dir "connectuser" $ hGet $ toK3 $ connectUserToSessionGet
    , dir "connectuser" $ hPostNoXToken $ toK3 $ connectUserToSessionPost
    , dir "connectcompany" $ hGet $ toK3 $ connectCompanyToSession
    ]


documentFromParam:: Kontrakcja m => IntegrationAPIFunction m Document
documentFromParam = do
    srvs <- service <$> ask
    mdocument <- liftMM (runDBQuery . GetDocumentByDocumentID) $ maybeReadM $ fromJSONField "document_id"
    when (isNothing mdocument || (not $ sameService srvs mdocument)) $ throwApiError API_ERROR_NO_DOCUMENT "No document exists"
    return $ fromJust mdocument

embeddDocumentFrame :: (CryptoRNG m, Kontrakcja m) => IntegrationAPIFunction m APIResponse
embeddDocumentFrame = do
    ctx <- getContext
    srvs <-  service <$> ask
    let sid = serviceid srvs
    let slocation = fromMaybe (ctxhostpart ctx) $ (BS.toString . unServiceLocation) <$> (servicelocation $ servicesettings srvs)
    let returnLink l =  return $ toJSObject [ ("link",JSString $ toJSString $ slocation ++ show l)]
    location <- fold <$> fromJSONField "location"
    doc <- documentFromParam
    mcomp <- lift_M (runDBUpdate . GetOrCreateCompanyWithExternalID  (Just sid)) (fmap ExternalCompanyID <$> fromJSONField "company_id")
    when (isNothing mcomp) $ throwApiError API_ERROR_MISSING_VALUE "At least company connected to document must be provided."
    let comp = fromJust mcomp
    when (not $ isAuthoredByCompany (companyid comp) doc) $ throwApiError API_ERROR_NO_DOCUMENT "No document exists"
    msiglink <- liftMM (\(bs::BS.ByteString) -> return $ getSigLinkFor doc bs) (fromJSONField "email")
    case msiglink of
         Nothing -> do
             when (not $ sameService srvs comp) $ throwApiError API_ERROR_MISSING_VALUE "Not matching company | This should never happend"
             ssid <- createServiceSession (Left $ companyid $ comp) location
             returnLink $ LinkConnectCompanySession sid (companyid comp) ssid $ LinkIssueDoc (documentid doc)
         Just siglink -> do
             if (isAuthor siglink && (isJust $ maybesignatory siglink))
                then do
                     muser <- runDBQuery $ GetUserByID $ fromJust $ maybesignatory siglink
                     when (not $ sameService sid muser && sameService srvs comp) $ throwApiError API_ERROR_MISSING_VALUE "Not matching user or company| This should never happend"
                     ssid <- createServiceSession (Right $ fromJust $ maybesignatory siglink) location
                     returnLink $ LinkConnectUserSession sid  (fromJust $ maybesignatory siglink) ssid $ LinkIssueDoc (documentid doc)
                else do
                     when (not $ sameService srvs comp) $ throwApiError API_ERROR_MISSING_VALUE "Not matching company | This should never happend"
                     ssid <- createServiceSession (Left $ companyid $ comp) location
                     returnLink $ LinkConnectCompanySession sid (companyid comp) ssid $ LinkIssueDoc (documentid doc)



createDocument :: Kontrakcja m => IntegrationAPIFunction m APIResponse
createDocument = do
   sid <- serviceid <$> service <$> ask
   mcomp_id <- fmap ExternalCompanyID <$> fromJSONField "company_id"
   when (isNothing mcomp_id) $ 
    throwApiError API_ERROR_MISSING_VALUE "No company id provided"
   comp <- runDBUpdate $ GetOrCreateCompanyWithExternalID  (Just sid) (fromJust mcomp_id)
   mtitle <- fromJSONField "title"
   when (isNothing mtitle) $ throwApiError API_ERROR_MISSING_VALUE "No title provided"
   let title = fromJust mtitle
   files <- getFiles
   mtype <- liftMM (return . toSafeEnumInt) (fromJSONField "type")
   when (isNothing mtype) $
     throwApiError API_ERROR_MISSING_VALUE "BAD DOCUMENT TYPE"
   let doctype = fromJust mtype
   mtemplateids <- fromJSONField "template_id"
   Log.integration $ "got this template from json " ++ show mtemplateids
   involved  <- fmap (fromMaybe []) $ fromJSONLocal "involved" $ fromJSONLocalMapList $ 
        (getSignatoryTMP [SignatoryAuthor, SignatoryPartner]) : (repeat $ getSignatoryTMP [SignatoryPartner])
   
   mlocale <- fromJSONField "locale"
   tags <- fmap (fromMaybe []) $ fromJSONLocal "tags" $ fromJSONLocalMap $ do
     n <- fromJSONField "name"
     v <- fromJSONField "value"
     when (isNothing n || isNothing v) $ throwApiError API_ERROR_MISSING_VALUE "Missing tag name or value"
     return $ Just $ DocumentTag (fromJust n) (fromJust v)
   createFun <- case mtemplateids of
     Just templateids -> -- they want a template
       case maybeRead templateids of
         Nothing -> throwApiError API_ERROR_PARSING $ "Invalid documentid " ++ templateids
         Just templateid -> do
           mtemplate <- runDBQuery $ GetDocumentByDocumentID templateid
           case mtemplate of
             Nothing -> throwApiError API_ERROR_NO_DOCUMENT $ "The template you requested does not exits " ++ show templateids
             Just _template ->
               return $ createDocFromTemplate templateid title
     Nothing -> return $ createDocFromFiles title doctype files
   d <- createAPIDocument comp involved tags mlocale createFun
   doc <- updateDocumentWithDocumentUI d
   return $ toJSObject [ ("document_id",JSString $ toJSString $ show $ documentid doc)]

createDocFromTemplate ::(Kontrakcja m) =>
                        DocumentID
                        -> BS.ByteString
                        -> User
                        -> Maybe Company
                        -> MinutesTime
                        -> IntegrationAPIFunction m (Maybe Document)
createDocFromTemplate templateid title user mcompany time = do
  ctx <- getContext
  sid <- serviceid <$> service <$> ask
  let mecid = maybe Nothing companyexternalid mcompany
  let ia = IntegrationAPIActor time (ctxipnumber ctx) sid (BS.toString . unExternalCompanyID <$> mecid)
  edoc <- runDBUpdate $ SignableFromDocumentIDWithUpdatedAuthor user mcompany templateid ia
  when (isLeft edoc) $
    throwApiError API_ERROR_OTHER $ "Cannot create document!"
  let doc = fromRight edoc
  edoc' <- runDBUpdate $ SetDocumentTitle (documentid doc) title ia
  when (isLeft edoc') $
    Log.integration $ "Could not set title on doc " ++ show (documentid doc)
  return $ either (const $ Just doc) Just edoc'

createDocFromFiles :: (Kontrakcja m) =>
                      BS.ByteString
                      -> DocumentType
                      -> [(BS.ByteString, BS.ByteString)]
                      -> User
                      -> Maybe Company
                      -> MinutesTime
                      -> IntegrationAPIFunction m (Maybe Document)
createDocFromFiles title doctype files user mcompany time = do
  ctx <- getContext
  sid <- serviceid <$> service <$> ask
  let mecid = maybe Nothing companyexternalid mcompany
  let ia = IntegrationAPIActor time (ctxipnumber ctx) sid (BS.toString . unExternalCompanyID <$> mecid)
  edoc <- runDBUpdate $ NewDocument user mcompany title doctype ia
  case edoc of
    Left _ -> throwApiError API_ERROR_OTHER $ "Cannot create document"
    Right doc -> do
      let addAndAttachFile name content = do
            econtent14 <- liftIO $ preCheckPDF (ctxgscmd ctx) content
            content14 <- case econtent14 of
                         Left _ -> throwApiError API_ERROR_OTHER $ "Cannot handle uploaded data"
                         Right x -> return x
            file <- runDB $ dbUpdate $ NewFile name content14
            runDBUpdate $ AttachFile (documentid doc) (fileid file) ia
      mapM_ (uncurry addAndAttachFile) files
      return $ Just doc

updateDocumentWithDocumentUI :: Kontrakcja m => Document -> IntegrationAPIFunction m Document
updateDocumentWithDocumentUI doc = do
  ctx <- getContext    
  sid <- serviceid <$> service <$> ask
  let actor = IntegrationAPIActor (ctxtime ctx) (ctxipnumber ctx) sid Nothing
  mailfooter <- fromJSONField "mailfooter"
  ndoc <- runDBUpdate $ SetDocumentUI (documentid doc) ((documentui doc) {documentmailfooter = mailfooter}) actor
  return $ either (const doc) id ndoc

createAPIDocument :: Kontrakcja m
                  => Company
                  -> [SignatoryTMP]
                  -> [DocumentTag]
                  -> Maybe Locale
                  -> (User -> Maybe Company -> MinutesTime -> IntegrationAPIFunction m (Maybe Document))
                  -> IntegrationAPIFunction m Document
createAPIDocument _ [] _ _ _  =
    throwApiError API_ERROR_OTHER "One involved person must be provided"
createAPIDocument comp' (authorTMP:signTMPS) tags mlocale createFun = do
    sid <- serviceid <$> service <$> ask
    
    when (isNothing $ companyexternalid comp') $
      throwApiError API_ERROR_ILLEGAL_VALUE "The companyid must exist."
    let Just (ExternalCompanyID cid) = companyexternalid comp'
        
    when (not $ isAuthorTMP authorTMP) $
      throwApiError API_ERROR_ILLEGAL_VALUE "The first involved must be an author role."
  
    when (any isAuthorTMP signTMPS) $
      throwApiError API_ERROR_ILLEGAL_VALUE "Only one author is allowed."

    now <- liftIO $ getMinutesTime
    comp <- setCompanyInfoFromTMP authorTMP comp'
    docAuthor <- userFromTMP authorTMP comp
    ctx <- getContext
    mdoc <- createFun docAuthor (Just comp) now
    when (isNothing mdoc) $ throwApiError API_ERROR_OTHER "Problem creating a document | This may be because the company and author don't match"
    let doc = fromJust mdoc
        actor = IntegrationAPIActor (ctxtime ctx) (ctxipnumber ctx) sid (Just $ BS.toString cid)
    _ <- runDBUpdate $ SetDocumentFunctionality (documentid doc) AdvancedFunctionality actor
    _ <- runDBUpdate $ SetDocumentTags (documentid doc) tags actor
    when (isJust mlocale) $
      ignore $ runDBUpdate $ SetDocumentLocale (documentid doc) (fromJust mlocale) actor
    let sigdetails s =  (fst $ toSignatoryDetails1 s,[SignatoryPartner] <| (isSignatoryTMP s) |> [])
        authordetails s = (fst $ toSignatoryDetails1 s,[SignatoryAuthor,SignatoryPartner] <| (isSignatoryTMP s) |> [SignatoryAuthor])
        sigs = (authordetails authorTMP):(sigdetails <$> signTMPS)
    doc' <- runDBUpdate $ ResetSignatoryDetails (documentid doc) sigs actor
    when (isLeft doc') $ Log.integration $ "error creating document: " ++ fromLeft doc'
    when (isLeft doc') $ throwApiError API_ERROR_OTHER "Problem creating a document (SIGUPDATE) | This should never happend"
    return $ fromRight doc'

userFromTMP :: Kontrakcja m => SignatoryTMP -> Company -> IntegrationAPIFunction m User
userFromTMP uTMP comp = do
    sid <- serviceid <$> service <$> ask
    let remail = fold $ asValidEmail . BS.toString <$> email uTMP
    when (not $ isGood $ remail) $ throwApiError API_ERROR_OTHER "NOT valid email for first involved person"
    muser <- runDBQuery $ GetUserByEmail (Just sid) $ Email $ fromGood remail
    Context{ctxtime,ctxipnumber} <- getContext
    user <- case muser of
              Just u -> return u
              Nothing -> do
                password <- createPassword =<< randomBytes 12
                mu <- runDBUpdate $ AddUser (fold $ fstname uTMP,fold $ sndname uTMP) (fromGood remail) (Just password) False (Just sid) (Just $ companyid comp) (mkLocaleFromRegion defaultValue)
                when (isNothing mu) $ throwApiError API_ERROR_OTHER "Problem creating a user (BASE) | This should never happend"
                let u = fromJust mu
                tos_accepted <- runDBUpdate $ AcceptTermsOfService (userid u) (fromSeconds 0)
                when (not tos_accepted) $ throwApiError API_ERROR_OTHER "Problem creating a user (TOS) | This should never happend"
                mtosuser <- runDBQuery $ GetUserByID (userid u)
                when (isNothing mtosuser) $ throwApiError API_ERROR_OTHER "Problem reading a user (BASE) | This should never happend"
                let tosuser = fromJust mtosuser

                _ <- addUserIDSignTOSStatEvent (userid u) ctxtime (usercompany u) (userservice u)
                _ <- runDBUpdate $ LogHistoryAccountCreated (userid u) ctxipnumber ctxtime (Email $ fromGood remail) Nothing
                _ <- runDBUpdate $ LogHistoryTOSAccept (userid u) ctxipnumber ctxtime Nothing

                return tosuser
    info_set <- runDBUpdate $ SetUserInfo (userid user) (userinfo user)
            {
              userfstname = fromMaybe (getFirstName user) $ fstname uTMP
            , usersndname = fromMaybe (getFirstName user) $ sndname uTMP
            , userpersonalnumber = fromMaybe (getPersonalNumber user) $ personalnumber uTMP
            }
    when (not info_set) $ throwApiError API_ERROR_OTHER "Problem creating a user (INFO) | This should never happend"
    _ <- runDBUpdate $ LogHistoryUserInfoChanged (userid user) ctxipnumber ctxtime (userinfo user) 
                                                 ((userinfo user) { userfstname = fromMaybe (getFirstName user) $ fstname uTMP
                                                                  , usersndname = fromMaybe (getFirstName user) $ sndname uTMP
                                                                  , userpersonalnumber = fromMaybe (getPersonalNumber user) $ personalnumber uTMP
                                                                  }) 
                                                  Nothing
    company_set <- runDBUpdate $ SetUserCompany (userid user) (Just $ companyid comp)
    when (not company_set) $ throwApiError API_ERROR_OTHER "Problem creating a user (COMPANY) | This should never happend"
    Just user' <- runDBQuery $ GetUserByID $ userid user
    return user'

setCompanyInfoFromTMP :: Kontrakcja m => SignatoryTMP -> Company -> IntegrationAPIFunction m Company
setCompanyInfoFromTMP uTMP cmp = do
    info_set <- runDBUpdate $ SetCompanyInfo (companyid cmp) (companyinfo cmp)
                {
                  companyname = fromMaybe (getCompanyName cmp) $ company uTMP
                , Company.Model.companynumber = fromMaybe (getCompanyNumber cmp) $ Doc.SignatoryTMP.companynumber uTMP
                }
    when (not info_set) $ throwApiError API_ERROR_OTHER "Problem create a user (COMPANY INFO) | This should never happen"
    Just cmp' <- runDBQuery $ GetCompany $ companyid cmp
    return cmp'
    

getDocuments :: Kontrakcja m => IntegrationAPIFunction m APIResponse
getDocuments = do
    sid <- serviceid <$> service <$> ask
    mcompany_id <- fmap ExternalCompanyID <$> fromJSONField "company_id"
    when (isNothing mcompany_id) $ throwApiError API_ERROR_MISSING_VALUE "No company id provided"
    comp <- runDBUpdate $ GetOrCreateCompanyWithExternalID  (Just sid) (fromJust mcompany_id)
    tags <- fmap (fromMaybe []) $ fromJSONLocal "tags" $ fromJSONLocalMap $ do
                    n <- fromJSONField "name"
                    v <- fromJSONField "value"
                    when (isNothing n || isNothing v) $ throwApiError API_ERROR_MISSING_VALUE "Missing tag name or value"
                    return $ Just $ DocumentTag (fromJust n) (fromJust v)
    mFromDateString <- fromJSONField "from_date"
    mToDateString   <- fromJSONField "to_date"
    mFromState :: Maybe Int <- fromJSONField "from_state"
    mToState   :: Maybe Int <- fromJSONField "to_state"
    mFromDate <- case mFromDateString of
      Nothing -> return Nothing
      Just s  -> case parseMinutesTimeISO s of
        Just t  -> return $ Just t
        Nothing -> throwApiError API_ERROR_PARSING $ "from_date unrecognized format: " ++ show s
    mToDate <- case mToDateString of
      Nothing -> return Nothing
      Just s  -> case parseMinutesTimeISO s of
        Just t  -> return $ Just t
        Nothing -> throwApiError API_ERROR_PARSING $ "to_date unrecognized format: " ++ show s
    let allstatuses = [Preparation, Pending, Closed, Rejected, Timedout, Canceled, AwaitingAuthor, DocumentError ""]
        mstatuses   = case (mFromState, mToState) of
          (Nothing, Nothing) -> Nothing
          _ -> Just [s | s <- allstatuses
                       , maybe True (fromSafeEnum s >=) mFromState
                       , maybe True (fromSafeEnum s <=) mToState
                       ]
    linkeddocuments <- runDBQuery $ GetDocumentsByCompanyWithFiltering (Just sid) (companyid comp) tags mFromDate mToDate mstatuses
    api_docs <- sequence [api_document_read False d  
                         | d <- linkeddocuments
                         , isAuthoredByCompany (companyid comp) d
                         , not $ isDeletedFor $ getAuthorSigLink d
                         , not $ isAttachment d
                         -- we avoid filtering when the filter is not defined
                         --, maybe True (recentDate d >=) mFromDate
                         --, maybe True (recentDate d <=) mToDate
                         --, maybe True ((fromSafeEnum $ documentstatus d) >=) mFromState
                         --, maybe True ((fromSafeEnum $ documentstatus d) <=) mToState
                         ]
    return $ toJSObject $ [("documents"  , JSArray $ api_docs)] ++
                          ([] <| isNothing mFromDate  |> [("from_date",  showJSON $ showMinutesTimeForAPI (fromJust mFromDate ))]) ++
                          ([] <| isNothing mToDate    |> [("to_date",    showJSON $ showMinutesTimeForAPI (fromJust mToDate   ))]) ++
                          ([] <| isNothing mFromState |> [("from_state", showJSON $                       (fromJust mFromState))]) ++
                          ([] <| isNothing mToState   |> [("to_state",   showJSON $                       (fromJust mToState  ))])

getDocument :: Kontrakcja m => IntegrationAPIFunction m APIResponse
getDocument = do
    doc <- documentFromParam
    api_doc <- api_document_read True doc
    return $ toJSObject [("document",api_doc)]

setDocumentTag :: Kontrakcja m => IntegrationAPIFunction m APIResponse
setDocumentTag =  do
  doc <- documentFromParam
  mtag <- fromJSONLocal "tag" $ do
    liftM2 pairMaybe (fromJSONField "name") (fromJSONField "value")
  when (isNothing mtag) $ throwApiError API_ERROR_MISSING_VALUE "Could not read tag name or value"
  sid <- serviceid <$> service <$> ask
  Context{ctxtime,ctxipnumber} <- getContext
  let tags = addTag (documenttags doc) (fromJust mtag)
      actor = IntegrationAPIActor ctxtime ctxipnumber sid Nothing
  res <- runDBUpdate $ SetDocumentTags (documentid doc) tags actor
  when (isLeft res) $ throwApiError API_ERROR_NO_USER $ "Changing tag problem:" ++ fromLeft res
  return $ toJSObject []


removeDocument  :: Kontrakcja m => IntegrationAPIFunction m APIResponse
removeDocument = do
    Context{ctxtime, ctxipnumber} <- getContext
    sid <- serviceid <$> service <$> ask
    doc <- documentFromParam
    -- we only control the author through the integration api
    mauthor <- maybe (return Nothing)
                     (runDBQuery . GetUserByID)
                     (getAuthorSigLink doc >>= maybesignatory)
    when (isNothing mauthor) $ throwApiError API_ERROR_NO_USER $ "Error while removing a document: Failed to find author"
    let actor = IntegrationAPIActor ctxtime ctxipnumber sid Nothing
    res <- runDBUpdate $ ArchiveDocument (fromJust mauthor) (documentid doc) actor
    when (isLeft res) $ throwApiError API_ERROR_NO_DOCUMENT $ "Error while removing a document: " ++ fromLeft res
    return $ toJSObject []

{- | Call connect user to session (all passed as URL params)
     and redirect user to referer
-}
connectUserToSessionPost :: Kontrakcja m => ServiceID -> UserID -> SessionId -> m KontraLink
connectUserToSessionPost sid uid ssid = do
    matchingService <-sameService sid <$> (runDBQuery $ GetUserByID uid)
    when (not matchingService) mzero
    loaded <- loadServiceSession (Right uid) ssid
    -- just send back empty string
    when loaded $ finishWith $ toResponseBS (BS.fromString "text/html;charset=utf-8") (BSL.fromString "")
    mzero

connectUserToSessionGet :: Kontrakcja m => ServiceID -> UserID -> SessionId -> m Response
connectUserToSessionGet _sid _uid _ssid = do
  rq <- askRq
  let uri = rqUri rq
  Log.integration $ "uri: " ++ uri
  referer <- look "referer"
  Log.integration $ "referer: " ++ referer
  bdy <- renderTemplateFM "connectredirect" $ do
    field "url" uri
    field "referer" referer
  simpleResponse bdy

connectCompanyToSession :: Kontrakcja m => ServiceID -> CompanyID -> SessionId -> m KontraLink
connectCompanyToSession sid cid ssid = do
    matchingService <- sameService sid <$> (runDBQuery $ GetCompany cid)
    when (not matchingService) mzero
    loaded <- loadServiceSession (Left cid) ssid
    if (loaded)
     then return $ BackToReferer
     else mzero

getDaveDoc :: Kontrakcja m => IntegrationAPIFunction m APIResponse
getDaveDoc = do
  Just (JSString document_id) <- fromJSONField "document_id"
  let Just did = maybeRead $ fromJSString document_id
  doc <- runDBQuery $ GetDocumentByDocumentID did
  return $ toJSObject [("document", showJSON $ show doc)]
