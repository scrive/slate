-----------------------------------------------------------------------------
-- |
-- Module      :  Administration.AdministrationControl
-- Maintainer  :  mariusz@skrivapa.se
-- Stability   :  development
-- Portability :  portable
--
-- Handlers for all administrations tasks
--
-----------------------------------------------------------------------------
module Administration.AdministrationControl(
            adminonlyRoutes
          , daveRoutes
          , jsonCompanies -- for tests
          ) where

import Data.Char
import Data.Functor.Invariant
import Data.Label (modify)
import Data.Unjson
import Happstack.Server hiding (dir, https, path, simpleHTTP)
import Happstack.StaticRouting (Route, choice, dir)
import Log
import Text.JSON
import Text.JSON.Gen hiding (object)
import Text.StringTemplates.Templates
import qualified Data.Aeson as Aeson
import qualified Data.ByteString as BS
import qualified Data.ByteString.Base64 as B64
import qualified Data.ByteString.Char8 as BSC8
import qualified Data.ByteString.Lazy as BSL
import qualified Data.ByteString.UTF8 as BS
import qualified Data.Map as Map
import qualified Data.Text as T
import qualified Data.Unjson as Unjson
import qualified Text.StringTemplates.Fields as F

import Administration.AdministrationView
import AppView (renderFromBody, simpleHtmlResponse)
import BrandedDomain.BrandedDomain
import BrandedDomain.Model
import Chargeable.Model
import DB
import Doc.Action (postDocumentClosedActions)
import Doc.API.V2.DocumentAccess
import Doc.API.V2.JSON.Document
import Doc.API.V2.JSON.List
import Doc.DocInfo
import Doc.DocStateData
import Doc.DocumentID
import Doc.DocumentMonad (withDocumentID)
import Doc.Model
import Doc.Screenshot (Screenshot(..))
import Doc.SignatoryLinkID
import Doc.SignatoryScreenshots (SignatoryScreenshots(..))
import EvidenceLog.Model
import FeatureFlags.Model
import File.File
import File.Model
import File.Storage
import Happstack.Fields
import InputValidation
import InspectXML
import InspectXMLInstances ()
import InternalResponse
import IPAddress ()
import Kontra
import KontraLink
import Mails.Model
import MinutesTime
import PadApplication.Data (padAppModeFromText)
import Partner.Model
import Routing
import Theme.Control
import User.CallbackScheme.Model
import User.Email
import User.History.Model
import User.JSON
import User.UserControl
import User.UserView
import User.Utils
import UserGroup.Data
import UserGroup.Model
import UserGroupAccounts.Model
import Util.Actor
import Util.HasSomeUserInfo
import Util.MonadUtils
import Util.SignatoryLinkUtils
import Utils.Monoid
import qualified Company.CompanyControl as Company
import qualified Data.ByteString.RFC2397 as RFC2397
import qualified UserGroupAccounts.UserGroupAccountsControl as UserGroupAccounts

adminonlyRoutes :: Route (Kontra Response)
adminonlyRoutes =
  fmap onlySalesOrAdmin $ choice $ [
          hGet $ toK0 $ showAdminMainPage
        , dir "createuser" $ hPost $ toK0 $ handleCreateUser
        , dir "userslist" $ hGet $ toK0 $ jsonUsersList

        , dir "useradmin" $ hGet $ toK1 $ showAdminUsers
        , dir "useradmin" $ dir "details" $ hGet $ toK1 $ handleUserGetProfile
        , dir "useradmin" $ hPost $ toK1 $ handleUserChange
        , dir "useradmin" $ dir "changepassword" $ hPost $ toK1 $ handleUserPasswordChange

        , dir "useradmin" $ dir "deleteinvite" $ hPost $ toK2 $ handleDeleteInvite
        , dir "useradmin" $ dir "delete" $ hPost $ toK1 $ handleDeleteUser
        , dir "useradmin" $ dir "move" $ hPost $ toK1 $ handleMoveUserToDifferentCompany
        , dir "useradmin" $ dir "disable2fa" $ hPost $ toK1 $ handleDisable2FAForUser

        , dir "useradmin" $ dir "usagestats" $ dir "days" $ hGet $ toK1 handleAdminUserUsageStatsDays
        , dir "useradmin" $ dir "usagestats" $ dir "months" $ hGet $ toK1 handleAdminUserUsageStatsMonths

        , dir "useradmin" $ dir "sendinviteagain" $ hPost $ toK0 $ sendInviteAgain

        , dir "companyadmin" $ hGet $ toK1 $ showAdminCompany
        , dir "companyadmin" $ dir "details" $ hGet $ toK1 $ handleCompanyGetProfile

        , dir "companyadmin" $ hPost $ toK1 $ handleCompanyChange
        , dir "companyadmin" $ dir "merge" $ hPost $ toK1 $ handleMergeToOtherCompany

        , dir "companyadmin" $ dir "branding" $ Company.adminRoutes
        , dir "companyadmin" $ dir "users" $ hPost $ toK1 $ handlePostAdminCompanyUsers

        , dir "companyaccounts" $ hGet  $ toK1 $ UserGroupAccounts.handleUserGroupAccountsForAdminOnly
        , dir "companyadmin" $ dir "usagestats" $ dir "days" $ hGet $ toK1 handleAdminCompanyUsageStatsDays
        , dir "companyadmin" $ dir "usagestats" $ dir "months" $ hGet $ toK1 handleAdminCompanyUsageStatsMonths

        , dir "companyadmin" $ dir "getsubscription" $ hGet $ toK1 $ handleCompanyGetSubscription
        , dir "companyadmin" $ dir "updatesubscription" $ hPost $ toK1 $ handleCompanyUpdateSubscription

        , dir "documentslist" $ hGet $ toK0 $ jsonDocuments

        , dir "companies" $ hGet $ toK0 $ jsonCompanies

        , dir "brandeddomainslist" $ hGet $ toK0 $ jsonBrandedDomainsList
        , dir "brandeddomain" $ dir "create" $ hPost $ toK0 $ createBrandedDomain
        , dir "brandeddomain" $ dir "details" $ hGet $ toK1 $ jsonBrandedDomain
        , dir "brandeddomain" $ dir "details" $ dir "change" $ hPost $ toK1 $ updateBrandedDomain
        , dir "brandeddomain" $ dir "themes" $ hGet $ toK1 $ handleGetThemesForDomain
        , dir "brandeddomain" $ dir "newtheme" $ hPost $ toK2 $ handleNewThemeForDomain
        , dir "brandeddomain" $ dir "updatetheme" $ hPost $ toK2 $ handleUpdateThemeForDomain
        , dir "brandeddomain" $ dir "deletetheme" $ hPost $ toK2$ handleDeleteThemeForDomain
  ]

daveRoutes :: Route (Kontra Response)
daveRoutes =
  fmap onlyAdmin $ choice $ [
       dir "document"      $ hGet $ toK1 $ daveDocument
     , dir "document"      $ hGet $ toK2 $ daveSignatoryLink
     , dir "user"          $ hGet $ toK1 $ daveUser
     , dir "userhistory"   $ hGet $ toK1 $ daveUserHistory
     , dir "company"       $ hGet $ toK1 $ daveCompany
     , dir "reseal" $ hPost $ toK1 $ resealFile
     , dir "file"   $ hGet  $ toK2 $ daveFile
     , dir "backdoor" $ hGet $ handleBackdoorQuery
     , dir "randomscreenshot" $ hGet $ toK0 $ randomScreenshotForTest
    ]
{- | Main page. Redirects users to other admin panels -}
showAdminMainPage :: Kontrakcja m => m String
showAdminMainPage = onlySalesOrAdmin $ do
    ctx <- getContext
    adminMainPage ctx

{- | Process view for finding a user in basic administration -}
showAdminUsers :: Kontrakcja m => UserID -> m String
showAdminUsers uid = onlySalesOrAdmin $ do
  ctx <- getContext
  adminUserPage ctx uid

handleUserGetProfile:: Kontrakcja m => UserID -> m JSValue
handleUserGetProfile uid = onlySalesOrAdmin $ do
  user <- guardJustM $ dbQuery $ GetUserByID uid
  ug <- getUserGroupForUser user
  partners <- dbQuery GetPartners
  return $ userJSON user (companyFromUserGroup ug partners)

handleCompanyGetProfile:: Kontrakcja m => UserGroupID -> m JSValue
handleCompanyGetProfile ugid = onlySalesOrAdmin $ do
  ug <- guardJustM . dbQuery . UserGroupGet $ ugid
  partners <- dbQuery GetPartners
  return . companyJSON True $ companyFromUserGroup ug partners

showAdminCompany :: Kontrakcja m => UserGroupID -> m String
showAdminCompany ugid = onlySalesOrAdmin $ do
  ctx <- getContext
  adminCompanyPage ctx ugid

jsonCompanies :: Kontrakcja m => m JSValue
jsonCompanies = onlySalesOrAdmin $ do
    limit    <- guardJustM $ readField "limit"
    offset   <- guardJustM $ readField "offset"
    textFilter <- getField "text" >>= \case
                     Nothing -> return []
                     Just s -> return [UGFilterByString s]
    usersFilter <- isFieldSet "allCompanies" >>= \case
                     True ->  return []
                     False -> return [UGManyUsers]
    pplanFilter <- isFieldSet "nonFree" >>= \case
                     True ->  return [UGWithNonFreePricePlan]
                     False -> return []
    ugs <- dbQuery $ UserGroupsGetFiltered (textFilter ++ usersFilter ++ pplanFilter) (Just (offset, limit))
    runJSONGenT $ do
            valueM "companies" $ forM ugs $ \ug -> runJSONGenT $ do
              value "id"             . show . get ugID $ ug
              value "companyname"    . T.unpack . get ugName $ ug
              value "companynumber"  . T.unpack . get (ugaCompanyNumber . ugAddress) $ ug
              value "companyaddress" . T.unpack . get (ugaAddress       . ugAddress) $ ug
              value "companyzip"     . T.unpack . get (ugaZip           . ugAddress) $ ug
              value "companycity"    . T.unpack . get (ugaCity          . ugAddress) $ ug
              value "companycountry" . T.unpack . get (ugaCountry       . ugAddress) $ ug

jsonUsersList ::Kontrakcja m => m JSValue
jsonUsersList = onlySalesOrAdmin $ do
    limit    <- guardJustM $ readField "limit"
    offset   <- guardJustM $ readField "offset"
    textFilter <- getField "text" >>= \case
                     Nothing -> return []
                     Just s -> return [UserFilterByString s]
    sorting <- getField "tosSorting" >>= \case
                     Just "ascending"   -> return [Asc UserOrderByAccountCreationDate]
                     Just "descending" -> return [Desc UserOrderByAccountCreationDate]
                     _ -> return [Asc UserOrderByName]
    allUsers <- dbQuery $ GetUsersWithUserGroupNames textFilter sorting (offset,limit)

    runJSONGenT $ do
      valueM "users" $ forM (allUsers) $ \(user,ugname) -> runJSONGenT $ do
        value "id" $ show $ userid user
        value "username" $ getFullName user
        value "email"    $ getEmail user
        value "companyposition" $ usercompanyposition $ userinfo user
        value "company"  . T.unpack $ ugname
        value "phone"    $ userphone $ userinfo user
        value "tos"      $ formatTimeISO <$> (userhasacceptedtermsofservice user)
        value "twofactor_active" $ usertotpactive user


{- | Handling user details change. It reads user info change -}
handleUserChange :: Kontrakcja m => UserID -> m JSValue
handleUserChange uid = onlySalesOrAdmin $ do
  ctx <- getContext
  museraccounttype <- getField "useraccounttype"
  olduser <- guardJustM $ dbQuery $ GetUserByID uid
  user <- case (museraccounttype,useriscompanyadmin olduser) of
    (Just "companyadminaccount",  False) -> do
      --then we just want to make this account an admin
      newuser <- guardJustM $ do
        _ <- dbUpdate $ SetUserCompanyAdmin uid True
        _ <- dbUpdate $ LogHistoryDetailsChanged uid (get ctxipnumber ctx) (get ctxtime ctx)
             [("is_company_admin", "false", "true")]
             (userid <$> get ctxmaybeuser ctx)
        dbQuery $ GetUserByID uid
      return newuser
    (Just "companystandardaccount", True) -> do
      --then we just want to downgrade this account to a standard
      newuser <- guardJustM $ do
        _ <- dbUpdate $ SetUserCompanyAdmin uid False
        _ <- dbUpdate
                 $ LogHistoryDetailsChanged uid (get ctxipnumber ctx) (get ctxtime ctx)
                                            [("is_company_admin", "true", "false")]
                                            (userid <$> get ctxmaybeuser ctx)
        dbQuery $ GetUserByID uid
      return newuser
    _ -> return olduser
  infoChange <- getUserInfoChange
  let applyChanges = do
        _ <- dbUpdate $ SetUserInfo uid $ infoChange $ userinfo user
        _ <- dbUpdate
              $ LogHistoryUserInfoChanged uid (get ctxipnumber ctx) (get ctxtime ctx)
                    (userinfo user) (infoChange $ userinfo user)
                    (userid <$> get ctxmaybeuser ctx)
        settingsChange <- getUserSettingsChange
        _ <- dbUpdate $ SetUserSettings uid $ settingsChange $ usersettings user
        return ()
  if (useremail (infoChange $ userinfo user) /= useremail (userinfo user))
    then do
      -- email address changed, check if new one is not used
      mexistinguser <- dbQuery $ GetUserByEmail $ useremail $ infoChange $ userinfo user
      case mexistinguser of
        Just _ -> runJSONGenT $ value "changed" False
        Nothing -> do
          applyChanges
          runJSONGenT $ value "changed" True
    else do
      applyChanges
      runJSONGenT $ value "changed" True


{- | Handling user password change. -}
handleUserPasswordChange :: Kontrakcja m => UserID -> m JSValue
handleUserPasswordChange uid = onlySalesOrAdmin $ do
  user <- guardJustM $ dbQuery $ GetUserByID uid
  password <- guardJustM $ getField "password"
  passwordhash <- createPassword password
  ctx <- getContext
  let time     = get ctxtime ctx
      ipnumber = get ctxipnumber ctx
      admin    = get ctxmaybeuser ctx
  _ <- dbUpdate $ SetUserPassword (userid user) passwordhash
  _ <- dbUpdate $ LogHistoryPasswordSetup (userid user) ipnumber time (userid <$> admin)
  runJSONGenT $ value "changed" True

handleDeleteInvite :: Kontrakcja m => UserGroupID -> UserID -> m ()
handleDeleteInvite ugid uid = onlySalesOrAdmin $ do
  _ <- dbUpdate $ RemoveUserGroupInvite ugid uid
  return ()

handleDeleteUser :: Kontrakcja m => UserID -> m ()
handleDeleteUser uid = onlySalesOrAdmin $ do
  _ <- dbUpdate $ RemoveUserUserGroupInvites uid
  _ <- dbUpdate $ DeleteUserCallbackScheme uid
  _ <- dbUpdate $ DeleteUser uid
  return ()

handleDisable2FAForUser :: Kontrakcja m => UserID -> m ()
handleDisable2FAForUser uid = onlySalesOrAdmin $ do
  ctx <- getContext
  user <- guardJustM $ dbQuery $ GetUserByID uid
  if usertotpactive user
     then do
       r <- dbUpdate $ DisableUserTOTP uid
       if r
          then do
            _ <- dbUpdate $ LogHistoryTOTPDisable uid (get ctxipnumber ctx) (get ctxtime ctx)
            return ()
          else
            internalError
     else return ()

handleMoveUserToDifferentCompany :: Kontrakcja m => UserID -> m ()
handleMoveUserToDifferentCompany uid = onlySalesOrAdmin $ do
  ugid <- guardJustM $ readField "companyid"
  _ <- dbUpdate $ SetUserUserGroup uid ugid
  _ <- dbUpdate $ SetUserCompanyAdmin uid False
  return ()


handleMergeToOtherCompany :: Kontrakcja m => UserGroupID -> m ()
handleMergeToOtherCompany ugid_source = onlySalesOrAdmin $ do
  ugid_target <- guardJustM $ readField "companyid"
  users <- dbQuery $ UserGroupGetUsers ugid_source
  forM_ users $ \u -> do
      _ <- dbUpdate $ SetUserUserGroup (userid u) ugid_target
      return ()
  invites <- dbQuery $ UserGroupGetInvites ugid_source
  forM_ invites $ \i-> do
      _ <- dbUpdate $ RemoveUserGroupInvite ugid_source (inviteduserid i)
      return ()

{- | Handling company details change. It reads user info change -}
handleCompanyChange :: Kontrakcja m => UserGroupID -> m ()
handleCompanyChange ugid = onlySalesOrAdmin $ do
  ug <- guardJustM $ dbQuery $ UserGroupGet ugid
  mcompanyname <- getField "companyname"
  uginfochange <- getUserGroupSettingsChange
  ugaddresschange <- getUserGroupAddressChange

  mcompanypartnerid <- getOptionalField asValidPartnerID "companypartnerid"
  mnewparentugid <- case mcompanypartnerid of
    Nothing -> return Nothing
    Just partnerid -> do
      partners <- dbQuery GetPartners
      -- check, if this company is a partner. We must not set partner_id of partners.
      let thisUserGroupIsPartner = ugid `elem` (catMaybes $ fmap ptUserGroupID partners)
      case thisUserGroupIsPartner of
        True  -> internalError
        False -> (return . find ((==partnerid) . ptID) $ partners) >>= \case
          -- No partner corresponds to the ID supplied
          Nothing -> internalError
          Just newParent -> case ptDefaultPartner newParent of
            -- setting the default partnerID is the same as having no usergroup parent
            True -> return Nothing
            -- All non-default partners have usergroup set. `Just . fromJust` is only a guard.
            False -> return . Just . fromJust . ptUserGroupID $ newParent

  dbUpdate . UserGroupUpdate
    . set ugParentGroupID mnewparentugid
    . maybe id (set ugName . T.pack) mcompanyname
    . modify ugSettings uginfochange
    . modify ugAddress ugaddresschange
    $ ug
  return $ ()

handleCreateUser :: Kontrakcja m => m JSValue
handleCreateUser = onlySalesOrAdmin $ do
    email <- filter (/=' ') <$> map toLower <$> (guardJustM $ getField "email")
    fstname <- guardJustM $ getField "fstname"
    sndname <- guardJustM $ getField "sndname"
    lang <- guardJustM $ join <$> fmap langFromCode <$> getField "lang"
    ug <- dbUpdate . UserGroupCreate $ def
    muser <- createNewUserByAdmin email (fstname, sndname) (get ugID ug, True) lang
    runJSONGenT $ case muser of
      Nothing -> do
        value "success" False
        valueM "error_message" $ renderTemplate_ "flashMessageUserWithSameEmailExists"
      Just _ -> do
        value "success" True
        value "error_message" (Nothing :: Maybe String)

handlePostAdminCompanyUsers :: Kontrakcja m => UserGroupID -> m JSValue
handlePostAdminCompanyUsers ugid = onlySalesOrAdmin $ do
  email <- getCriticalField asValidEmail "email"
  fstname <- fromMaybe "" <$> getOptionalField asValidName "fstname"
  sndname <- fromMaybe "" <$> getOptionalField asValidName "sndname"
  lang <- guardJustM $ join <$> fmap langFromCode <$> getField "lang"
  admin <- isFieldSet "iscompanyadmin"
  muser <- createNewUserByAdmin email (fstname, sndname) (ugid, admin) lang
  runJSONGenT $ case muser of
    Nothing -> do
      value "success" False
      valueM "error_message" $ renderTemplate_ "flashMessageUserWithSameEmailExists"
    Just _ -> do
      value "success" True
      value "error_message" (Nothing :: Maybe String)

{- | Reads params and returns function for conversion of user group info.  With no param leaves fields unchanged -}
getUserGroupSettingsChange :: Kontrakcja m => m (UserGroupSettings -> UserGroupSettings)
getUserGroupSettingsChange = do
  mcompanyipaddressmasklist <- getOptionalField asValidIPAddressWithMaskList "companyipaddressmasklist"
  mcompanycgidisplayname <- fmap emptyToNothing <$> getField "companycgidisplayname"
  mcompanycgiserviceid <- fmap emptyToNothing <$> getField "companycgiserviceid"
  mcompanyidledoctimeout <- (>>= \s -> if null s
                                       then Just Nothing
                                       else Just <$> (do t <- maybeRead s
                                                         guard $ t >= minUserGroupIdleDocTimeout
                                                         guard $ t <= maxUserGroupIdleDocTimeout
                                                         return t)) <$> getField "companyidledoctimeout"
  mcompanysmsprovider <- fmap maybeRead <$> getField' $ "companysmsprovider"
  mcompanypadappmode <- fmap (padAppModeFromText . T.pack) <$> getField' $ "companypadappmode"
  mcompanypadearchiveenabled <- getField "companypadearchiveenabled"

  return $
      maybe id (set ugsIPAddressMaskList) mcompanyipaddressmasklist
    . maybe id (set ugsCGIDisplayName . fmap T.pack) mcompanycgidisplayname
    . maybe id (set ugsIdleDocTimeout) mcompanyidledoctimeout
    . maybe id (set ugsCGIServiceID . fmap T.pack) mcompanycgiserviceid
    . maybe id (set ugsSMSProvider) mcompanysmsprovider
    . maybe id (set ugsPadAppMode) mcompanypadappmode
    . maybe id (set ugsPadEarchiveEnabled . (=="true")) mcompanypadearchiveenabled

{- | Reads params and returns function for conversion of user group address.  With no param leaves fields unchanged -}
getUserGroupAddressChange :: Kontrakcja m => m (UserGroupAddress -> UserGroupAddress)
getUserGroupAddressChange = do
  mcompanynumber  <- getField "companynumber"
  mcompanyaddress <- getField "companyaddress"
  mcompanyzip     <- getField "companyzip"
  mcompanycity    <- getField "companycity"
  mcompanycountry <- getField "companycountry"
  return $
      maybe id (set ugaCompanyNumber . T.pack) mcompanynumber
    . maybe id (set ugaAddress . T.pack) mcompanyaddress
    . maybe id (set ugaZip . T.pack) mcompanyzip
    . maybe id (set ugaCity . T.pack) mcompanycity
    . maybe id (set ugaCountry . T.pack) mcompanycountry

{- | Reads params and returns function for conversion of user settings.  No param leaves fields unchanged -}
getUserSettingsChange :: Kontrakcja m => m (UserSettings -> UserSettings)
getUserSettingsChange = do
  mlang <- join <$> fmap langFromCode <$> getField "userlang"
  return $ \settings -> settings {
     lang = fromMaybe (lang settings) mlang
  }

{- | Reads params and returns function for conversion of user info. With no param leaves fields unchanged -}
getUserInfoChange :: Kontrakcja m => m (UserInfo -> UserInfo)
getUserInfoChange = do
  muserfstname         <- getField "userfstname"
  musersndname         <- getField "usersndname"
  muserpersonalnumber  <- getField "userpersonalnumber"
  musercompanyposition <- getField "usercompanyposition"
  muserphone           <- getField "userphone"
  museremail           <- fmap Email <$> getField "useremail"
  return $ \UserInfo{..} -> UserInfo {
        userfstname         = fromMaybe userfstname muserfstname
      , usersndname         = fromMaybe usersndname musersndname
      , userpersonalnumber  = fromMaybe userpersonalnumber muserpersonalnumber
      , usercompanyposition = fromMaybe usercompanyposition musercompanyposition
      , userphone           = fromMaybe userphone muserphone
      , useremail           = fromMaybe useremail museremail
    }

jsonDocuments :: Kontrakcja m => m Response
jsonDocuments = onlyAdmin $ do
  adminUser <- guardJustM $ get ctxmaybeuser <$> getContext
  muid <- readField "userid"
  mugid <- readField "companyid"
  offset   <- guardJustM $ readField "offset"
  maxcount <- guardJustM $ readField  "max"

  requestedFilters <- getFieldBS "filter" >>= \case
      Just paramValue -> case Aeson.eitherDecode paramValue of
         Right js -> case (Unjson.parse Unjson.unjsonDef js) of
            (Result res []) -> return $ join $ toDocumentFilter (userid adminUser) <$> res
            _ -> internalError
         Left _ -> internalError
      Nothing -> return []

  requestedSorting <- getFieldBS "sorting" >>= \case
      Just paramValue -> case Aeson.eitherDecode paramValue of
         Right js -> case (Unjson.parse Unjson.unjsonDef js) of
            (Result res []) -> return $ toDocumentSorting <$> res
            _ -> internalError
         Left _ -> internalError
      Nothing -> return []

  let (domain,filtering, sorting)     = case (mugid, muid) of
        -- When fetching all documents, we don't allow any filtering, and only default sort is allowed
        (Nothing, Nothing)   -> (DocumentsOfWholeUniverse,[],[Desc DocumentOrderByMTime])
        (Just ugid, Nothing) -> (DocumentsOfUserGroup ugid,requestedFilters,requestedSorting)
        (Nothing, Just uid)  -> (DocumentsVisibleToUser uid, requestedFilters,requestedSorting)
        _                    -> unexpectedError "Can't pass both user id and company id"
  (allDocsCount, allDocs) <- dbQuery $ GetDocumentsWithSoftLimit domain filtering sorting (offset, 1000, maxcount)
  let json = listToJSONBS (allDocsCount,(\d -> (documentAccessForAdminonly d,d)) <$> allDocs)
  return $ Response 200 Map.empty nullRsFlags json Nothing


handleBackdoorQuery :: Kontrakcja m => m Response
handleBackdoorQuery = onlySalesOrAdmin $ onlyBackdoorOpen $ do
  emailAddress <- guardJustM $ getField "email_address"
  emailTitle <- guardJustM $ getField "email_title"
  Just startDate <- MinutesTime.parseTimeISO <$> (guardJustM $ getField "start_date")
  memail <- dbQuery $ GetEmailForRecipient emailAddress emailTitle startDate
  case memail of
    Nothing -> respond404
    Just email -> renderFromBody $ mailContent email

sendInviteAgain :: Kontrakcja m => m InternalKontraResponse
sendInviteAgain = onlySalesOrAdmin $ do
  uid <- guardJustM $ readField "userid"
  user <- guardJustM $ dbQuery $ GetUserByID uid
  sendNewUserMail user
  flashmessage <- flashMessageNewActivationLinkSend
  return $ internalResponseWithFlash flashmessage LoopBack

-- This method can be used to reseal a document
resealFile :: Kontrakcja m => DocumentID -> m KontraLink
resealFile docid = onlyAdmin $ withDocumentID docid $ do
  logInfo_ "Trying to reseal document (only superadmin can do that)"
  ctx <- getContext
  actor <- guardJust $ mkAdminActor ctx
  _ <- dbUpdate $ InsertEvidenceEvent
          ResealedPDF
          (return ())
          actor
  void $ postDocumentClosedActions False True
  return LoopBack


{- |
   Used by super users to inspect a particular document.
-}
daveDocument :: Kontrakcja m => DocumentID -> m (Either KontraLink String)
daveDocument documentid = onlyAdmin $ do
    -- for dave, we want a slash at the end, so redirect if there is no slash
    -- we have a relative link for signatorylinkids, so we need a slash at the end
    -- of the dave/document links; I evaluated a few other ways (using javascript, etc)
    -- but I could not come up with a better one than this
    --  -Eric
    location <- rqUri <$> askRq
    logInfo "Logging location" $ object [
        "location" .= location
      ]
    if "/" `isSuffixOf` location
     then do
      document <- dbQuery $ GetDocumentForDave documentid
      r <- renderTemplate "daveDocument" $ do
        F.value "daveBody" $  inspectXML document
        F.value "id" $ show documentid
        F.value "closed" $ documentstatus document == Closed
        F.value "couldBeclosed" $ isDocumentError document && all (isSignatory --> hasSigned) (documentsignatorylinks document)
      return $ Right r
     else return $ Left $ LinkDaveDocument documentid

{- |
   Used by super users to inspect a particular signatory link.
-}
daveSignatoryLink :: Kontrakcja m => DocumentID -> SignatoryLinkID -> m  String
daveSignatoryLink documentid siglinkid = onlyAdmin $ do
    document <- dbQuery $ GetDocumentByDocumentID documentid
    siglink <- guardJust $ getSigLinkFor siglinkid document
    renderTemplate  "daveSignatoryLink" $ do
        F.value "daveBody" $ inspectXML siglink

{- |
   Used by super users to inspect a particular user.
-}
daveUser :: Kontrakcja m => UserID ->  m String
daveUser userid = onlyAdmin $ do
    user <- guardJustM $ dbQuery $ GetUserByID userid
    return $ inspectXML user

{- |
   Used by super users to inspect a particular user's history.
-}
daveUserHistory :: Kontrakcja m => UserID -> m String
daveUserHistory userid = onlyAdmin $ do
    history <- dbQuery $ GetUserHistoryByUserID userid
    return $ inspectXML history

{- |
    Used by super users to inspect a company in xml.
-}
daveCompany :: Kontrakcja m => UserGroupID -> m String
daveCompany ugid = onlyAdmin $ do
  ug <- guardJustM . dbQuery . UserGroupGet $ ugid
  partners <- dbQuery GetPartners
  return . inspectXML $ companyFromUserGroup ug partners

daveFile :: Kontrakcja m => FileID -> String -> m Response
daveFile fileid' _title = onlyAdmin $ do
   file <- dbQuery $ GetFileByFileID fileid'
   contents <- getFileContents file
   if BS.null contents
      then internalError
      else do
        let fname = filter (/=',') $ filename file -- Chrome does not like commas in this header
        return $ setHeader "Content-Disposition" ("attachment;filename=" ++ fname)
                 $ Response 200 Map.empty nullRsFlags (BSL.fromChunks [contents]) Nothing

randomScreenshotForTest :: Kontrakcja m => m Response
randomScreenshotForTest = do
  now <- currentTime
  let lastWeek = 7 `daysBefore` now
  slid <- guardJustM $ dbQuery $ GetRandomSignatoryLinkIDThatSignedRecently lastWeek
  screenshots <- map snd <$> dbQuery (GetSignatoryScreenshots [slid])
  doc <- dbQuery $ GetDocumentBySignatoryLinkID slid
  elogEvents <- dbQuery $ GetEvidenceLog $ documentid doc
  let sigElogEvents = filter ((== Just slid) . evSigLink) elogEvents
  content <- renderTemplate "screenshotReview" $ do
    F.value "userAgent" $ evClientName <$> find (isJust . evClientName) sigElogEvents
    F.value "signatoryid" $ show slid
    case screenshots of
      ((SignatoryScreenshots mfirst msigning _):_) -> do
        let screenShowImageString (Screenshot _ img) = BS.toString $ RFC2397.encode "image/jpeg" img
        F.value "firstimage" $ screenShowImageString <$> mfirst
        F.value "signingimage" $ screenShowImageString <$> msigning
      _ -> return ()
  simpleHtmlResponse content

handleAdminUserUsageStatsDays :: Kontrakcja m => UserID -> m JSValue
handleAdminUserUsageStatsDays uid = onlySalesOrAdmin $ do
  user <- guardJustM $ dbQuery $ GetUserByID uid
  withCompany <- isFieldSet "withCompany"
  if (useriscompanyadmin user && withCompany)
    then getDaysStats (Right $ usergroupid user)
    else getDaysStats (Left $ userid user)


handleAdminUserUsageStatsMonths :: Kontrakcja m => UserID -> m JSValue
handleAdminUserUsageStatsMonths uid = onlySalesOrAdmin $ do
  user <- guardJustM $ dbQuery $ GetUserByID uid
  withCompany <- isFieldSet "withCompany"
  if (useriscompanyadmin user && withCompany)
    then getMonthsStats (Right $ usergroupid user)
    else getMonthsStats (Left $ userid user)

handleAdminCompanyUsageStatsDays :: Kontrakcja m => UserGroupID -> m JSValue
handleAdminCompanyUsageStatsDays ugid = onlySalesOrAdmin $ do
  getDaysStats (Right $ ugid)

handleAdminCompanyUsageStatsMonths :: Kontrakcja m => UserGroupID -> m JSValue
handleAdminCompanyUsageStatsMonths ugid = onlySalesOrAdmin $ do
  getMonthsStats (Right $ ugid)

handleCompanyGetSubscription :: Kontrakcja m => UserGroupID -> m JSValue
handleCompanyGetSubscription ugid = onlySalesOrAdmin $ do
  ug <- guardJustM . dbQuery . UserGroupGet $ ugid
  users <- dbQuery . UserGroupGetUsers $ ugid
  docsStartedThisMonth <- fromIntegral <$> (dbQuery $ GetNumberOfDocumentsStartedThisMonth $ ugid)
  ff <- dbQuery $ GetFeatureFlags ugid
  return $ subscriptionJSON ug users docsStartedThisMonth ff

handleCompanyUpdateSubscription :: Kontrakcja m => UserGroupID -> m ()
handleCompanyUpdateSubscription ugid = onlySalesOrAdmin $ do
  paymentPlan <- guardJustM $ join <$> fmap paymentPlanFromText <$> getField "payment_plan"
  ug <- guardJustM . dbQuery . UserGroupGet $ ugid
  let new_invoicing = case get ugInvoicing ug of
        None         -> None
        BillItem mpp -> BillItem . fmap (const paymentPlan) $ mpp
        Invoice _    -> Invoice paymentPlan
  dbUpdate . UserGroupUpdate . set ugInvoicing new_invoicing $ ug

  canUseTemplates <- fmap ((==) "true") $ guardJustM $ getField "can_use_templates"
  canUseBranding <- fmap ((==) "true") $ guardJustM $ getField "can_use_branding"
  canUseAuthorAttachments  <- fmap ((==) "true") $ guardJustM $ getField "can_use_author_attachments"
  canUseSignatoryAttachments  <- fmap ((==) "true") $ guardJustM $ getField "can_use_signatory_attachments"
  canUseMassSendout  <- fmap ((==) "true") $ guardJustM $ getField "can_use_mass_sendout"

  canUseSMSInvitations  <- fmap ((==) "true") $ guardJustM $ getField "can_use_sms_invitations"
  canUseSMSConfirmations  <- fmap ((==) "true") $ guardJustM $ getField "can_use_sms_confirmations"

  canUseDKAuthenticationToView  <- fmap ((==) "true") $ guardJustM $ getField "can_use_dk_authentication_to_view"
  canUseDKAuthenticationToSign  <- fmap ((==) "true") $ guardJustM $ getField "can_use_dk_authentication_to_sign"
  canUseNOAuthenticationToView  <- fmap ((==) "true") $ guardJustM $ getField "can_use_no_authentication_to_view"
  canUseNOAuthenticationToSign  <- fmap ((==) "true") $ guardJustM $ getField "can_use_no_authentication_to_sign"
  canUseSEAuthenticationToView  <- fmap ((==) "true") $ guardJustM $ getField "can_use_se_authentication_to_view"
  canUseSEAuthenticationToSign  <- fmap ((==) "true") $ guardJustM $ getField "can_use_se_authentication_to_sign"
  canUseSMSPinAuthenticationToSign  <- fmap ((==) "true") $ guardJustM $ getField "can_use_sms_pin_authentication_to_sign"
  canUseSMSPinAuthenticationToView  <- fmap ((==) "true") $ guardJustM $ getField "can_use_sms_pin_authentication_to_view"

  _ <- dbUpdate $ UpdateFeatureFlags ugid $ FeatureFlags {
      ffCanUseTemplates = canUseTemplates
    , ffCanUseBranding = canUseBranding
    , ffCanUseAuthorAttachments = canUseAuthorAttachments
    , ffCanUseSignatoryAttachments = canUseSignatoryAttachments
    , ffCanUseMassSendout = canUseMassSendout
    , ffCanUseSMSInvitations = canUseSMSInvitations
    , ffCanUseSMSConfirmations = canUseSMSConfirmations
    , ffCanUseDKAuthenticationToView = canUseDKAuthenticationToView
    , ffCanUseDKAuthenticationToSign = canUseDKAuthenticationToSign
    , ffCanUseNOAuthenticationToView = canUseNOAuthenticationToView
    , ffCanUseNOAuthenticationToSign = canUseNOAuthenticationToSign
    , ffCanUseSEAuthenticationToView = canUseSEAuthenticationToView
    , ffCanUseSEAuthenticationToSign = canUseSEAuthenticationToSign
    , ffCanUseSMSPinAuthenticationToSign = canUseSMSPinAuthenticationToSign
    , ffCanUseSMSPinAuthenticationToView = canUseSMSPinAuthenticationToView
    }
  return ()

jsonBrandedDomainsList ::Kontrakcja m => m Aeson.Value
jsonBrandedDomainsList = onlySalesOrAdmin $ do
    allBrandedDomains <- dbQuery $ GetBrandedDomains
    return $ Unjson.unjsonToJSON' (Options { pretty = True, indent = 2, nulls = True }) unjsonBrandedDomainsList allBrandedDomains

jsonBrandedDomain :: Kontrakcja m => BrandedDomainID -> m Aeson.Value
jsonBrandedDomain bdID = onlySalesOrAdmin $ do
  bd <- dbQuery $ GetBrandedDomainByID bdID
  return $ Unjson.unjsonToJSON' (Options { pretty = True, indent = 2, nulls = True }) unjsonBrandedDomain bd

updateBrandedDomain :: Kontrakcja m => BrandedDomainID -> m ()
updateBrandedDomain xbdid = onlySalesOrAdmin $ do
    obd <- dbQuery $ GetBrandedDomainByID xbdid
    when (get bdMainDomain obd) $ do
      logInfo_ "Main domain can't be changed"
      internalError
    -- keep this 1to1 consistent with fields in the database
    domainJSON <- guardJustM $ getFieldBS "domain"
    case Aeson.eitherDecode $ domainJSON of
     Left err -> do
      logInfo "Error while parsing branding for adminonly" $ object [
          "error" .= err
        ]
      internalError
     Right js -> case (Unjson.parse unjsonBrandedDomain js) of
        (Result newDomain []) -> do
          _ <- dbUpdate $ UpdateBrandedDomain $
                 copy bdid obd $
                 copy bdMainDomain obd $
                 newDomain
          return ()
        _ -> internalError

unjsonBrandedDomain :: UnjsonDef BrandedDomain
unjsonBrandedDomain = objectOf $ pure BrandedDomain
  <*> field "id"
      (get bdid)
      "Id of a branded domain (unique)"
  <*> field "mainDomain"
      (get bdMainDomain)
      "Is this a main domain"
  <*> field "url"
      (get bdUrl)
      "URL that will match this domain"
  <*> field "smsOriginator"
      (get bdSmsOriginator)
      "Originator for text messages"
  <*> field "emailOriginator"
      (get bdEmailOriginator)
      "Originator for email messages"
  <*> field "mailTheme"
      (get bdMailTheme)
      "Email theme"
  <*> field "signviewTheme"
      (get bdSignviewTheme)
      "Signview theme"
  <*> field "serviceTheme"
      (get bdServiceTheme)
      "Service theme"
  <*> field "loginTheme"
      (get bdLoginTheme)
      "Login theme"
  <*> field "browserTitle"
      (get bdBrowserTitle)
      "Browser title"
  <*> fieldBy "favicon"
      (get bdFavicon)
      "Favicon"
       (invmap
          (\l -> B64.decodeLenient $ BSC8.pack $  drop 1 $ dropWhile ((/=) ',') l)
          (\l -> BSC8.unpack $ BS.append (BSC8.pack "data:image/png;base64,") $ B64.encode l)
          unjsonDef
       )
   <*> field "participantColor1"
      (get bdParticipantColor1)
      "Participant 1 color"
   <*> field "participantColor2"
      (get bdParticipantColor2)
      "Participant 2 color"
   <*> field "participantColor3"
      (get bdParticipantColor3)
      "Participant 3 color"
   <*> field "participantColor4"
      (get bdParticipantColor4)
      "Participant 4 color"
   <*> field "participantColor5"
      (get bdParticipantColor5)
      "Participant 5 color"
   <*> field "participantColor6"
      (get bdParticipantColor6)
      "Participant 6 color"
   <*> field "draftColor"
      (get bdDraftColor)
      "Draft color"
   <*> field "cancelledColor"
      (get bdCancelledColor)
      "Cancelled color"
   <*> field "initatedColor"
      (get bdInitatedColor)
      "Initated color"
   <*> field "sentColor"
      (get bdSentColor)
      "Sent color"
   <*> field "deliveredColor"
      (get bdDeliveredColor)
      "Delivered color"
   <*> field "openedColor"
      (get bdOpenedColor)
      "Opened color"
   <*> field "reviewedColor"
      (get bdReviewedColor)
      "Reviewed color"
   <*> field "signedColor"
      (get bdSignedColor)
      "Signed color"

unjsonBrandedDomainsList :: UnjsonDef [BrandedDomain]
unjsonBrandedDomainsList = objectOf $
  fieldBy "domains"
  id
  "List of branded domains"
  (arrayOf unjsonBrandedDomain)


createBrandedDomain :: Kontrakcja m => m JSValue
createBrandedDomain = do
    bdID <- dbUpdate $ NewBrandedDomain
    runJSONGenT $ do
      value "id" (show bdID)
