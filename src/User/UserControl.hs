module User.UserControl where

import Control.Monad.State
import Data.Char
import Data.Either (lefts, rights)
import Data.Functor
import Data.List
import Data.Maybe
import Happstack.Server hiding (simpleHTTP)
import Happstack.State (update, query)
import System.Random
import qualified Data.ByteString.Char8 as BS
import qualified Data.ByteString.UTF8 as BS
import Text.JSON (JSValue(..), toJSObject, toJSString)

import ActionSchedulerState
import AppView
import DB.Classes
import DB.Types
import Doc.DocState
import Company.Model
import InputValidation
import Kontra
import KontraLink
import ListUtil
import Mails.SendMail
import MinutesTime
import Misc
import Redirect
import Templates.Templates
import User.Model
import User.UserView
import Util.FlashUtil
import Util.HasSomeCompanyInfo
import Util.HasSomeUserInfo
import Util.SignatoryLinkUtils
import qualified AppLogger as Log
import Util.KontraLinkUtils
import Util.MonadUtils


checkPasswordsMatch :: TemplatesMonad m => BS.ByteString -> BS.ByteString -> Either (m FlashMessage) ()
checkPasswordsMatch p1 p2 =
    if p1 == p2
       then Right ()
       else Left flashMessagePasswordsDontMatch

{- |
    This is really a util function that I couldn't figure out a better
    place for.  TODO put in better place!
    
    This looks up the company for the given user, if the user doesn't
    have a company then it returns Nothing.
-}
getCompanyForUser :: Kontrakcja m => User -> m (Maybe Company)
getCompanyForUser user =
  case usercompany user of
    Just companyid -> runDBQuery $ GetCompany companyid
    _ -> return Nothing

handleUserGet :: Kontrakcja m => m Response
handleUserGet = do
    ctx <- getContext
    case (ctxmaybeuser ctx) of
         Just user -> do
           mcompany <- getCompanyForUser user
           showUser user mcompany >>= renderFromBody TopAccount kontrakcja
         Nothing -> sendRedirect $ LinkLogin (ctxregion ctx) (ctxlang ctx) NotLogged

handleUserPost :: Kontrakcja m => m KontraLink
handleUserPost = do
    ctx <- getContext
    case (ctxmaybeuser ctx) of
         Just user -> do
             infoUpdate <- getUserInfoUpdate
             _ <- runDBUpdate $ SetUserInfo (userid user) (infoUpdate $ userinfo user)
             mcompany <- getCompanyForUser user
             case (useriscompanyadmin user, mcompany) of
               (True, Just company) -> do
                 companyinfoupdate <- getCompanyInfoUpdate
                 _ <- runDBUpdate $ SetCompanyInfo (companyid company) (companyinfoupdate $ companyinfo company)
                 return ()
               _ -> return ()
             addFlashM flashMessageUserDetailsSaved
             return LinkAccount
         Nothing -> return $ LinkLogin (ctxregion ctx) (ctxlang ctx) NotLogged

getUserInfoUpdate :: Kontrakcja m => m (UserInfo -> UserInfo)
getUserInfoUpdate  = do
    -- a lot doesn't have validation rules defined, but i put in what we do have
    mfstname          <- getValidField asValidName "fstname"
    msndname          <- getValidField asValidName "sndname"
    mpersonalnumber   <- getFieldUTF "personalnumber"
    mphone            <- getFieldUTF "phone"
    mcompanyposition  <- getValidField asValidPosition "companyposition"
    return $ \ui ->
        ui {
            userfstname = fromMaybe (userfstname ui) mfstname
          , usersndname = fromMaybe (usersndname ui) msndname
          , userpersonalnumber = fromMaybe (userpersonalnumber ui) mpersonalnumber
          , usercompanyposition = fromMaybe (usercompanyposition ui) mcompanyposition
          , userphone  = fromMaybe (userphone ui) mphone
        }
    where
        getValidField = getDefaultedField BS.empty

getCompanyInfoUpdate :: Kontrakcja m => m (CompanyInfo -> CompanyInfo)
getCompanyInfoUpdate = do
    -- a lot doesn't have validation rules defined, but i put in what we do have
  mcompanyname <- getValidField asValidCompanyName "companyname"
  mcompanynumber <- getValidField asValidCompanyNumber "companynumber"
  mcompanyaddress <- getValidField asValidAddress "companyaddress"
  mcompanyzip <- getFieldUTF "companyzip"
  mcompanycity <- getFieldUTF "companycity"
  mcompanycountry <- getFieldUTF "companycountry"
  return $ \ci ->
      ci {
         companyname = fromMaybe (companyname ci) mcompanyname
      ,  companynumber = fromMaybe (companynumber ci) mcompanynumber
      ,  companyaddress = fromMaybe (companyaddress ci) mcompanyaddress
      ,  companyzip = fromMaybe (companyzip ci) mcompanyzip
      ,  companycity = fromMaybe (companycity ci) mcompanycity
      ,  companycountry = fromMaybe (companycountry ci) mcompanycountry
      }
  where
    getValidField = getDefaultedField BS.empty

handleGetUserMailAPI :: Kontrakcja m => m (Either KontraLink Response)
handleGetUserMailAPI = withUserGet $ do
    Context{ctxmaybeuser = Just user@User{userid}} <- getContext
    mapi <- runDBQuery $ GetUserMailAPI userid
    showUserMailAPI user mapi >>= renderFromBody TopAccount kontrakcja

handlePostUserMailAPI :: Kontrakcja m => m KontraLink
handlePostUserMailAPI = withUserPost $ do
    User{userid} <- fromJust . ctxmaybeuser <$> getContext
    mapi <- runDBQuery $ GetUserMailAPI userid
    getDefaultedField False asValidCheckBox "api_enabled"
      >>= maybe (return LinkUserMailAPI) (\enabledapi -> do
        case mapi of
             Nothing -> do
                 when enabledapi $ do
                     apikey <- liftIO randomIO
                     _ <- runDBUpdate $ SetUserMailAPI userid $ Just UserMailAPI {
                           umapiKey = apikey
                         , umapiDailyLimit = 50
                         , umapiSentToday = 0
                     }
                     return ()
             Just api -> do
                 if not enabledapi
                    then do
                        _ <- runDBUpdate $ SetUserMailAPI userid Nothing
                        return ()
                    else do
                        mresetkey <- getDefaultedField False asValidCheckBox "reset_key"
                        mresetsenttoday <- getDefaultedField False asValidCheckBox "reset_senttoday"
                        mdailylimit <- getRequiredField asValidNumber "daily_limit"
                        case (mresetkey, mresetsenttoday, mdailylimit) of
                             (Just resetkey, Just resetsenttoday, Just dailylimit) -> do
                                 newkey <- if resetkey
                                   then liftIO randomIO
                                   else return $ umapiKey api
                                 _ <- runDBUpdate $ SetUserMailAPI userid $ Just api {
                                       umapiKey = newkey
                                     , umapiDailyLimit = max 1 dailylimit
                                     , umapiSentToday = if resetsenttoday
                                                           then 0
                                                           else umapiSentToday api
                                 }
                                 return ()
                             _ -> return ()
        return LinkUserMailAPI)

handleGetUserSecurity :: Kontrakcja m => m Response
handleGetUserSecurity = do
    ctx <- getContext
    case (ctxmaybeuser ctx) of
         Just user -> showUserSecurity user >>= renderFromBody TopAccount kontrakcja
         Nothing -> sendRedirect $ LinkLogin (ctxregion ctx) (ctxlang ctx) NotLogged

handlePostUserLocale :: Kontrakcja m => m KontraLink
handlePostUserLocale = do
  ctx <- getContext
  user <- guardJust $ ctxmaybeuser ctx
  mregion <- readField "region"
  let newregion = fromMaybe (region $ usersettings user) mregion
  _ <- runDBUpdate $ SetUserSettings (userid user) $ (usersettings user) {
           region = newregion
         , lang = defaultRegionLang newregion
         }
  return LoopBack
  

handlePostUserSecurity :: Kontrakcja m => m KontraLink
handlePostUserSecurity = do
  ctx <- getContext
  case (ctxmaybeuser ctx) of
    Just user -> do
      moldpassword <- getOptionalField asDirtyPassword "oldpassword"
      mpassword <- getOptionalField asValidPassword "password"
      mpassword2 <- getOptionalField asDirtyPassword "password2"
      case (moldpassword, mpassword, mpassword2) of
        (Just oldpassword, Just password, Just password2) ->
          case (verifyPassword (userpassword user) oldpassword,
                  checkPasswordsMatch password password2) of
            (False,_) ->
              addFlashM flashMessageBadOldPassword
            (_, Left f) ->
              addFlashM f
            _ ->  do
              passwordhash <- liftIO $ createPassword password
              _ <- runDBUpdate $ SetUserPassword (userid user) passwordhash
              addFlashM flashMessageUserDetailsSaved
        _ | isJust moldpassword || isJust mpassword || isJust mpassword2 ->
              addFlashM flashMessageMissingRequiredField
        _ -> return ()
      mregion <- readField "region"
      let newregion = fromMaybe (region $ usersettings user) mregion
      _ <- runDBUpdate $ SetUserSettings (userid user) $ (usersettings user) {
             region = fromMaybe (region $ usersettings user) mregion
           , lang = defaultRegionLang newregion
           }
      return LinkAccountSecurity
    Nothing -> return $ LinkLogin (ctxregion ctx) (ctxlang ctx) NotLogged

handleGetSharing :: Kontrakcja m => m (Either KontraLink Response)
handleGetSharing = withUserGet $ do
    Context{ctxmaybeuser = Just user@User{userid}} <- getContext
    friends <- runDBQuery $ GetUserFriends userid
    params <- getListParams
    viewFriends (friendsSortSearchPage params friends) user
        >>= renderFromBody TopAccount kontrakcja

-- Searching, sorting and paging
friendsSortSearchPage :: ListParams -> [User] -> PagedList User
friendsSortSearchPage  =
    listSortSearchPage companyAccountsSortFunc companyAccountsSearchFunc companyAccountsPageSize

handleGetCompanyAccounts :: Kontrakcja m => m (Either KontraLink Response)
handleGetCompanyAccounts = withUserGet $ withCompanyAdmin $ \companyid -> do
    Context{ctxmaybeuser = Just user} <- getContext
    companyaccounts <- runDBQuery $ GetCompanyAccounts companyid
    params <- getListParams
    content <- viewCompanyAccounts user (companyAccountsSortSearchPage params $ companyaccounts)
    renderFromBody TopAccount kontrakcja content

-- Searching, sorting and paging
companyAccountsSortSearchPage :: ListParams -> [User] -> PagedList User
companyAccountsSortSearchPage  =
    listSortSearchPage companyAccountsSortFunc companyAccountsSearchFunc companyAccountsPageSize

companyAccountsSearchFunc :: SearchingFunction User
companyAccountsSearchFunc s user = userMatch user s -- split s so we support spaces
    where
        match s' m = isInfixOf (map toUpper s') (map toUpper (BS.toString m))
        userMatch u s' = match s' (usercompanyposition $ userinfo u)
                      || match s' (getFirstName u)
                      || match s' (getLastName  u)
                      || match s' (getPersonalNumber u)
                      || match s' (getEmail u)

companyAccountsSortFunc :: SortingFunction User
companyAccountsSortFunc "fstname" = viewComparing getFirstName
companyAccountsSortFunc "fstnameREV" = viewComparingRev getFirstName
companyAccountsSortFunc "sndname" = viewComparing getLastName
companyAccountsSortFunc "sndnameREV" = viewComparingRev getLastName
companyAccountsSortFunc "companyposition" = viewComparing $ usercompanyposition . userinfo
companyAccountsSortFunc "companypositionREV" = viewComparingRev $ usercompanyposition . userinfo
companyAccountsSortFunc "phone" = viewComparing $  userphone . userinfo
companyAccountsSortFunc "phoneREV" = viewComparingRev $ userphone . userinfo
companyAccountsSortFunc "email" = viewComparing getEmail
companyAccountsSortFunc "emailREV" = viewComparingRev getEmail
companyAccountsSortFunc _ = const $ const EQ

companyAccountsPageSize :: Int
companyAccountsPageSize = 20

----

handlePostSharing :: Kontrakcja m => m KontraLink
handlePostSharing = do
    ctx <- getContext
    case ctxmaybeuser ctx of
         Just user -> do
             memail <- getOptionalField asValidEmail "email"
             remove <- isFieldSet "remove"
             case (memail,remove) of
                  (Just email,_) -> do
                      handleAddFriend user email
                      return $ LinkSharing emptyListParams
                  (_,True) -> return $ LinkSharing emptyListParams
                  _ -> LinkSharing <$> getListParamsForSearch
         Nothing -> return $ LinkLogin (ctxregion ctx) (ctxlang ctx) NotLogged

handleAddFriend :: Kontrakcja m => User -> BS.ByteString -> m ()
handleAddFriend User{userid} email = do
    avereturn <- runDBUpdate $ AddViewerByEmail userid $ Email email
    when (not avereturn) $ do
      -- FIXME: display sane error msg here (as template)
      addFlash (OperationFailed, "operation failed")

handlePostCompanyAccounts :: Kontrakcja m => m KontraLink
handlePostCompanyAccounts = do
    ctx <- getContext
    case (ctxmaybeuser ctx) of
         Just user -> do
             add <- isFieldSet "add"
             remove <- isFieldSet "remove"
             takeover <- isFieldSet "takeover"
             case (add,remove,takeover) of
                  (True, _, _) -> do
                    handleCreateCompanyUser user
                    return $ LinkCompanyAccounts emptyListParams
                  (_, True, _) -> handleDeleteCompanyUser user
                  (_, _, True) -> do
                      memail <- getOptionalField asValidEmail "email"
                      handleTakeOverUserForCompany (fromJust memail)
                      return $ LinkCompanyAccounts emptyListParams
                  _ -> LinkCompanyAccounts <$> getListParamsForSearch
         Nothing -> return $ LinkLogin (ctxregion ctx) (ctxlang ctx) NotLogged

handleDeleteCompanyUser :: Kontrakcja m => User -> m KontraLink
handleDeleteCompanyUser user = do
  companyaccountsids <- getCriticalFieldList asValidNumber "acccheck"
  handleUserDelete user (map UserID companyaccountsids)
  return $ LinkCompanyAccounts emptyListParams

{- |
    Deletes a list of users one at a time.  It first checks the permissions
    for all users, and if it's okay for all it deletes them all.  Otherwise
    it deletes no-one.
-}
handleUserDelete :: Kontrakcja m => User -> [UserID] -> m ()
handleUserDelete deleter deleteeids = do
  mcompanyaccounts <- mapM (getUserDeletionDetails (userid deleter)) deleteeids
  case lefts mcompanyaccounts of
    (NoDeletionRights:_) -> mzero
    (UserHasLiveDocs:_) -> do
      addFlashM flashMessageUserHasLiveDocs
      return ()
    [] -> do
      mapM_ performUserDeletion (rights mcompanyaccounts)
      addFlashM flashMessageAccountsDeleted
      return ()

type UserDeletionDetails = (User, [Document])

data UserDeletionProblem = NoDeletionRights | UserHasLiveDocs

getUserDeletionDetails :: Kontrakcja m => UserID -> UserID -> m (Either UserDeletionProblem UserDeletionDetails)
getUserDeletionDetails deleterid deleteeid = do
  deleter <- runDBOrFail $ dbQuery $ GetUserByID deleterid
  deletee <- runDBOrFail $ dbQuery $ GetUserByID deleteeid
  let isSelfDelete = deleterid == deleteeid
      isAdminDelete = maybe False ((== (usercompany deleter)) . Just) (usercompany deletee)
      isPermissioned = isSelfDelete || isAdminDelete
  userdocs <- query $ GetDocumentsByUser deletee  --maybe this should be GetDocumentsBySignatory, but what happens to things yet to be activated?
  let isAllDeletable = all isDeletableDocument userdocs
  case (isPermissioned, isAllDeletable) of
    (False, _) -> return $ Left NoDeletionRights
    (_, False) -> return $ Left UserHasLiveDocs
    _ -> return $ Right (deletee, userdocs)

performUserDeletion :: Kontrakcja m => UserDeletionDetails -> m ()
performUserDeletion (user, docs) = do
  _ <- runDBUpdate $ DeleteUser $ userid user
  idsAndUsers <- mapM (lookupUsersRelevantToDoc . documentid) docs
  mapM_ (\iu -> update $ DeleteDocumentRecordIfRequired  (fst iu) (snd iu)) idsAndUsers

{- |
    This looks up all the users relevant for the given docid.
    This is the dodgy link between documents and users and is required
    when deleting a user or deleting a doc.  Bleurgh.
-}
lookupUsersRelevantToDoc :: Kontrakcja m => DocumentID -> m (DocumentID, [User])
lookupUsersRelevantToDoc docid = do
  doc <- queryOrFail $ GetDocumentByDocumentID docid
  musers <- mapM (runDBQuery . GetUserByID) (linkedUserIDs doc)
  return $ (docid, catMaybes musers)
  where
    linkedUserIDs = catMaybes . map maybesignatory . documentsignatorylinks

handleTakeOverUserForCompany :: Kontrakcja m => BS.ByteString -> m ()
handleTakeOverUserForCompany email = do
  ctx@Context{ctxmaybeuser = Just companyadmin} <- getContext
  Just invited <- runDBQuery $ GetUserByEmail Nothing (Email email)
  mail <- mailInviteUserAsCompanyAccount ctx invited companyadmin
  scheduleEmailSendout (ctxesenforcer ctx) $ mail { to = [getMailAddress invited] }
  addFlashM flashMessageUserInvitedAsCompanyAccount

handleCreateCompanyUser :: Kontrakcja m => User -> m ()
handleCreateCompanyUser user = when (useriscompanyadmin user) $ do
    ctx <- getContext
    memail <- getOptionalField asValidEmail "email"
    fstname <- maybe "" id <$> getField "fstname"
    sndname <- maybe "" id <$> getField "sndname"
    let fullname = (BS.fromString fstname, BS.fromString sndname)
    case memail of
      Just email -> do
        mcompany <- getCompanyForUser user
        muser <- createUser ctx fullname email (Just user) mcompany False
        case muser of
          Just newuser -> do
            infoUpdate <- getUserInfoUpdate
            _ <- runDBUpdate $ SetUserInfo (userid newuser) (infoUpdate $ userinfo newuser)
            return ()
          Nothing -> do
            Just invuser <- runDBQuery $ GetUserByEmail Nothing $ Email email
            case usercompany invuser of
              Nothing -> addFlashM $ modalInviteUserAsCompanyAccount fstname sndname (BS.toString email)
              Just cid | fromJust (usercompany user) == cid -> addFlashM flashUserIsAlreadyCompanyAccount
              _ ->
                -- this is the case when companyid of invited user doesn't
                -- match inviter's one. even if it's highly unlikely to
                -- happen, I guess we should handle this case somehow.
                return ()
            return ()
      _ -> return ()

handleViralInvite :: Kontrakcja m => m KontraLink
handleViralInvite = withUserPost $ do
  getOptionalField asValidEmail "invitedemail" >>= maybe (return ())
    (\invitedemail -> do
        ctx@Context{ctxmaybeuser = Just user} <- getContext
        muser <- runDBQuery $ GetUserByEmail Nothing $ Email invitedemail
        if isJust muser
           -- we leak user information here! SECURITY!!!!
           -- you can find out if a given email is already a user
          then addFlashM flashMessageUserWithSameEmailExists
          else do
            now <- liftIO getMinutesTime
            minv <- checkValidity now <$> (query $ GetViralInvitationByEmail $ Email invitedemail)
            case minv of
              Just Action{ actionID, actionType = ViralInvitationSent{ visEmail
                                                                     , visTime
                                                                     , visInviterID
                                                                     , visRemainedEmails
                                                                     , visToken } } -> do
                if visInviterID == userid user
                  then case visRemainedEmails of
                    0 -> addFlashM flashMessageNoRemainedInvitationEmails
                    n -> do
                      _ <- update $ UpdateActionType actionID $ ViralInvitationSent { visEmail = visEmail
                                                                                    , visTime = visTime
                                                                                    , visInviterID = visInviterID
                                                                                    , visRemainedEmails = n -1
                                                                                    , visToken = visToken }
                      sendInvitation ctx (LinkViralInvitationSent actionID $ visToken) invitedemail
                  else addFlashM flashMessageOtherUserSentInvitation
              _ -> do
                link <- newViralInvitationSentLink (Email invitedemail) (userid . fromJust $ ctxmaybeuser ctx)
                sendInvitation ctx link invitedemail
        )
  return LoopBack
    where
      sendInvitation ctx link invitedemail = do
        addFlashM flashMessageViralInviteSent
        mail <- viralInviteMail ctx invitedemail link
        scheduleEmailSendout (ctxesenforcer ctx) $ mail { to = [MailAddress { fullname = BS.empty, email = invitedemail }]}

randomPassword :: IO BS.ByteString
randomPassword =
    BS.fromString <$> randomString 8 (['0'..'9'] ++ ['A'..'Z'] ++ ['a'..'z'])


createUser :: Kontrakcja m => Context
                                  -> (BS.ByteString, BS.ByteString)
                                  -> BS.ByteString
                                  -> Maybe User
                                  -> Maybe Company
                                  -> Bool
                                  -> m (Maybe User)
createUser ctx names email madminuser mcompany' vip = do
  passwd <- liftIO $ createPassword =<< randomPassword
  -- make sure we don't count the company unless the admin user actually is a company admin user
  let mcompany = case (fmap useriscompanyadmin madminuser,
                       madminuser >>= usercompany,
                       mcompany') of
                   (Just True, Just adminusercompanyid, Just company)
                     | adminusercompanyid == companyid company -> mcompany'
                   _ -> Nothing
  let Context{ctxhostpart, ctxregion, ctxlang} = ctx
  muser <- runDBUpdate $ AddUser names email (Just passwd) False Nothing (fmap companyid mcompany) (systemServerFromURL ctxhostpart) ctxregion ctxlang
  case muser of
    Just user -> do
      let fullname = composeFullName names
      mail <- case (madminuser, mcompany) of
                (Just adminuser, Just company) -> do
                  al <- newAccountCreatedLink user
                  inviteCompanyAccountMail ctxhostpart (getSmartName adminuser) (getCompanyName company) email fullname al
                _ -> do
                  al <- newAccountCreatedLink user
                  newUserMail ctxhostpart email fullname al vip
      scheduleEmailSendout (ctxesenforcer ctx) $ mail { to = [MailAddress { fullname = fullname, email = email }]}
      return muser
    Nothing -> return muser

createUserBySigning :: Kontrakcja m => (BS.ByteString, BS.ByteString) -> BS.ByteString -> (DocumentID, SignatoryLinkID) -> m (Maybe (User, ActionID, MagicHash))
createUserBySigning names email doclinkdata =
    createInvitedUser names email Nothing >>= maybe (return Nothing) (\user -> do
        (actionid, magichash) <- newAccountCreatedBySigningLink user doclinkdata
        return $ Just (user, actionid, magichash)
    )

createNewUserByAdmin :: Kontrakcja m => Context -> (BS.ByteString, BS.ByteString) -> BS.ByteString -> Maybe MinutesTime -> Maybe String -> SystemServer -> Region -> Lang -> m (Maybe User)
createNewUserByAdmin ctx names email _freetill custommessage ss r l = do
    muser <- createInvitedUser names email (Just (ss, r, l))
    case muser of
         Just user -> do
             let fullname = composeFullName names
             now <- liftIO $ getMinutesTime
             _ <- runDBUpdate $ SetInviteInfo (userid <$> ctxmaybeuser ctx) now Admin (userid user)
             chpwdlink <- newAccountCreatedLink user
             mail <- mailNewAccountCreatedByAdmin ctx fullname email chpwdlink custommessage
             scheduleEmailSendout (ctxesenforcer ctx) $ mail { to = [MailAddress { fullname = fullname, email = email }]}
             return muser
         Nothing -> return muser 

createInvitedUser :: Kontrakcja m => (BS.ByteString, BS.ByteString) -> BS.ByteString -> Maybe (SystemServer, Region, Lang) -> m (Maybe User)
createInvitedUser names email mlocale = do
    Context{ctxhostpart, ctxregion, ctxlang} <- getContext
    let (ss, r, l) = fromMaybe (systemServerFromURL ctxhostpart, ctxregion, ctxlang) mlocale
    passwd <- liftIO $ createPassword =<< randomPassword
    runDBUpdate $ AddUser names email (Just passwd) False Nothing Nothing ss r l

{- |
   Guard against a POST with no logged in user.
   If they are not logged in, redirect to login page.
-}
withUserPost :: Kontrakcja m => m KontraLink -> m KontraLink
withUserPost action = do
    ctx <- getContext
    case ctxmaybeuser ctx of
         Just _  -> action
         Nothing -> return $ LinkLogin (ctxregion ctx) (ctxlang ctx) NotLogged

{- |
   Guard against a GET with no logged in user.
   If they are not logged in, redirect to login page.
-}
withUserGet :: Kontrakcja m => m a -> m (Either KontraLink a)
withUserGet action = do
  ctx <- getContext
  case ctxmaybeuser ctx of
    Just _  -> Right <$> action
    Nothing -> return $ Left $ LinkLogin (ctxregion ctx) (ctxlang ctx) NotLogged

{- |
   Runs an action only if currently logged in user is a company admin
-}
withCompanyAdmin :: Kontrakcja m => (CompanyID -> m a) -> m a
withCompanyAdmin action = do
  ctx <- getContext
  User{useriscompanyadmin, usercompany} <- guardJust $ ctxmaybeuser ctx
  guard $ useriscompanyadmin && isJust usercompany
  action $ fromJust usercompany
{- |
     Takes a document and a action
     Runs an action only if current user (from context) is author of document
| -}
withDocumentAuthor :: Kontrakcja m => Document -> m a -> m a
withDocumentAuthor document action = do
  ctx <- getContext
  user <- guardJust $ ctxmaybeuser ctx
  sl <- guardJust $ getAuthorSigLink document
  guard $ isSigLinkFor user sl
  action

{- |
   Guard against a GET with logged in users who have not signed the TOS agreement.
   If they have not, redirect to their account page.
-}
checkUserTOSGet :: Kontrakcja m => m a -> m (Either KontraLink a)
checkUserTOSGet action = do
    ctx <- getContext
    case ctxmaybeuser ctx of
        Just (User{userhasacceptedtermsofservice = Just _}) -> Right <$> action
        Just _ -> return $ Left $ LinkAcceptTOS
        Nothing -> case (ctxcompany ctx) of
             Just _company -> Right <$> action
             Nothing -> return $ Left $ LinkLogin (ctxregion ctx) (ctxlang ctx) NotLogged



handleAcceptTOSGet :: Kontrakcja m => m (Either KontraLink Response)
handleAcceptTOSGet = withUserGet $ do
    renderFromBody TopNone kontrakcja =<< pageAcceptTOS

handleAcceptTOSPost :: Kontrakcja m => m KontraLink
handleAcceptTOSPost = withUserPost $ do
  Context{ctxmaybeuser = Just User{userid}, ctxtime} <- getContext
  tos <- getDefaultedField False asValidCheckBox "tos"
  case tos of
    Just True -> do
      _ <- runDBUpdate $ AcceptTermsOfService userid ctxtime
      addFlashM flashMessageUserDetailsSaved
      return LinkUpload
    Just False -> do
      addFlashM flashMessageMustAcceptTOS
      return LinkAcceptTOS
    Nothing -> return LinkAcceptTOS

handleQuestion :: Kontrakcja m => m KontraLink
handleQuestion = do
    ctx <- getContext
    name <- getField "name"
    memail <- getDefaultedField BS.empty asValidEmail "email"
    phone <- getField "phone"
    message <- getField "message"
    case memail of
         Nothing -> return LoopBack
         Just email -> do
             let content = "name: "    ++ fromMaybe "" name ++ "<BR/>"
                        ++ "email: "   ++ BS.toString email ++ "<BR/>"
                        ++ "phone "    ++ fromMaybe "" phone ++ "<BR/>"
                        ++ "message: " ++ fromMaybe "" message
             scheduleEmailSendout (ctxesenforcer ctx) $ emptyMail {
                   to = [MailAddress { fullname = BS.fromString "info@skrivapa.se", email = BS.fromString "info@skrivapa.se" }]
                 , title = BS.fromString $ "Question"
                 , content = BS.fromString $ content
             }
             addFlashM flashMessageThanksForTheQuestion
             return LoopBack

handleGetBecomeCompanyAccount :: Kontrakcja m => UserID -> m (Either KontraLink Response)
handleGetBecomeCompanyAccount _supervisorid = withUserGet $ do
  addFlashM modalDoYouWantToBeCompanyAccount
  Context{ctxmaybeuser = Just user} <- getContext
  mcompany <- getCompanyForUser user
  content <- showUser user mcompany
  renderFromBody TopAccount kontrakcja content

handlePostBecomeCompanyAccount :: Kontrakcja m => UserID -> m KontraLink
handlePostBecomeCompanyAccount supervisorid = withUserPost $ do
  ctx@Context{ctxmaybeuser = Just user} <- getContext
  supervisor <- fromMaybe user <$> (runDBQuery $ GetUserByID supervisorid)
  case (userid user /= supervisorid, usercompany supervisor) of
     (True, Just companyid) -> do
          setcompanyresult <- runDBUpdate $ SetUserCompany (userid user) companyid
          if setcompanyresult
            then do
              addFlashM $ flashMessageUserHasBecomeCompanyAccount supervisor
              mail <- mailCompanyAccountAccepted ctx user supervisor
              scheduleEmailSendout (ctxesenforcer ctx) $ mail { to = [getMailAddress supervisor] }
            else do
              -- FIXME: why this is exposed as flash message? We need this as template.
              let msg = "Cannot become company account"
              Log.debug msg
              addFlash (OperationFailed, msg)
          return LinkAccount
     _ -> return LinkAccount

handleAccountSetupGet :: Kontrakcja m => ActionID -> MagicHash -> m Response
handleAccountSetupGet aid hash = do
    now <- liftIO $ getMinutesTime
    maction <- do
        (query $ GetAction aid) >>= maybe (return Nothing) (\action -> do
            -- action may be in state when it has expired, but hasn't yet been
            -- transformed into next form. below code checks for that.
            if (actionTypeID $ actionType action) == AccountCreatedBySigningID && (acbsState $ actionType action) /= ReminderSent
               then return $ Just action
               else return $ checkValidity now $ Just action)
    case maction of
         Just action ->
             case actionType action of
                  ViralInvitationSent _ _ _ _ token ->
                      if token == hash
                         then activationPage Nothing Nothing
                         else mzero
                  AccountCreatedBySigning _ uid _ token -> do
                      if token == hash
                         then (runDBQuery $ GetUserByID uid) >>= (\mu -> activationPage mu Nothing)
                         else mzero
                  AccountCreated uid token -> do
                      if token == hash
                         then (runDBQuery $ GetUserByID uid) >>= maybe mzero (\user -> do
                             if isNothing $ userhasacceptedtermsofservice user
                                then do
                                  mcompany <- getCompanyForUser user
                                  activationPage (Just user) mcompany
                                else do
                                  addFlashM flashMessageUserAlreadyActivated
                                  sendRedirect LinkUpload)
                         else mzero
                  _  -> mzero
         Nothing -> do
             muser <- liftMM (runDBQuery . GetUserByEmail Nothing . Email) (getOptionalField asValidEmail "email")
             case muser of
                  Just user ->
                    if isNothing  $ join $ userhasacceptedtermsofservice <$> muser
                     then do
                        let email = getEmail user
                        content <- activatePageViewNotValidLink $ BS.toString email
                        renderFromBody TopNone kontrakcja content
                    else mzero
                  Nothing -> mzero
    where
      activationPage muser mcompany = do
        extendActionEvalTimeToOneDayMinimum aid
        addFlashM $ modalAccountSetup muser mcompany $ LinkAccountCreated aid hash $ maybe "" (BS.toString . getEmail) muser
        linkmain <- getHomeOrUploadLink
        sendRedirect linkmain

handleAccountSetupFromSign :: Kontrakcja m => ActionID -> MagicHash -> m (Maybe User)
handleAccountSetupFromSign aid hash = do
  Log.debug "Account setup after signing document"  
  muserid <- getUserIDFromAction
  Log.debug $ "Account setup after signing document: UserID->"  ++ (show muserid)
  case muserid of
    Just userid -> do
      user <- runDBOrFail $ dbQuery $ GetUserByID userid
      Log.debug $ "Account setup after signing document: Matching user->"  ++ (BS.toString $ getEmail user)    
      handleActivate aid hash BySigning user
    Nothing -> return Nothing
  where
    getUserIDFromAction :: Kontrakcja m => m (Maybe UserID)
    getUserIDFromAction = do
      now <- liftIO $ getMinutesTime
      maction <- checkValidity now <$> (query $ GetAction aid)
      case maction of
        Just action ->
          case actionType action of
            AccountCreatedBySigning _ uid _ token ->
              if token == hash
                then do
                  return $ Just uid
                else return Nothing
            _ -> return Nothing
        _-> return Nothing

handleAccountSetupPost :: Kontrakcja m => ActionID -> MagicHash -> m KontraLink
handleAccountSetupPost aid hash = do
  now <- liftIO $ getMinutesTime
  maction <- checkValidity now <$> (query $ GetAction aid)
  case fmap actionType maction of
    Just (ViralInvitationSent email invtime inviterid _ token) ->
      if token == hash
         then do
           _ <- (getUserForViralInvite email invtime inviterid)
                 >>= maybe mzero (handleActivate aid hash ViralInvitation)
           getHomeOrUploadLink
         else mzero
    Just (AccountCreatedBySigning _ uid _ token) ->
      if token == hash
        then do
          _ <- (runDBQuery $ GetUserByID uid)
                  >>= maybe mzero (handleActivate aid hash BySigning)
          addFlashM modalWelcomeToSkrivaPa
          getHomeOrUploadLink
        else mzero
    Just (AccountCreated uid token) ->
      if token == hash
        then (runDBQuery $ GetUserByID uid) >>= maybe mzero (\user ->
          if isNothing $ userhasacceptedtermsofservice user
            then do
              _ <- handleActivate aid hash AccountRequest user
              getHomeOrUploadLink
            else do
              addFlashM flashMessageUserAlreadyActivated
              getHomeOrUploadLink)
        else mzero
    Just _ -> mzero
    Nothing -> do -- try to generate another activation link
      getOptionalField asValidEmail "email" >>= maybe mzero (\email ->
        (runDBQuery $ GetUserByEmail Nothing $ Email email) >>= maybe mzero (\user ->
          if isNothing $ userhasacceptedtermsofservice user
            then do
              ctx <- getContext
              al <- newAccountCreatedLink user
              mail <- newUserMail (ctxhostpart ctx) email email al False
              scheduleEmailSendout (ctxesenforcer ctx) $ mail { to = [MailAddress { fullname = email, email = email}] }
              addFlashM flashMessageNewActivationLinkSend
              getHomeOrUploadLink
            else mzero))
  where
    getUserForViralInvite :: Kontrakcja m => Email -> MinutesTime -> UserID -> m (Maybe User)
    getUserForViralInvite invitedemail invitationtime inviterid = do
      muser <- createInvitedUser (BS.empty, BS.empty) (unEmail invitedemail) Nothing
      case muser of
        Just user -> do -- user created, we need to fill in some info
          minviter <- runDBQuery $ GetUserByID inviterid
          _ <- runDBUpdate $ SetInviteInfo (userid <$> minviter) invitationtime Viral (userid user)
          return muser
        Nothing -> do -- user already exists, get her
          runDBQuery $ GetUserByEmail Nothing invitedemail

handleActivate :: Kontrakcja m => ActionID -> MagicHash -> SignupMethod -> User -> m (Maybe User)
handleActivate aid hash signupmethod actvuser = do
  Log.debug $ "Activating user account: "  ++ (BS.toString $ getEmail actvuser)
  iscompanyaccount <- getOptionalField asValidAccountType "accounttype"
  mcompany <- getCompanyForUser actvuser
  case (iscompanyaccount, mcompany) of
    (Nothing, _) -> do
      Log.debug "Activating user account: No account type set"
      addFlashM flashMessageNoAccountType
      return Nothing
    (Just False, Just _company) -> do
      -- accounts setup as part of a company can't just switch to being private
      -- we have protected against this on the client, but this should provide an extra server check
      addFlashM flashMessageNoAccountType
      returnToAccountSetup actvuser Nothing
    (Just False, Nothing) ->
      -- this is just a simple private account activation
      finalizePrivateActivation actvuser
    (Just True, Just company) -> do
      -- this is an account for an existing company
      finalizeCompanyActivation actvuser company
    (Just True, Nothing) -> do
      -- we need to make a new company, because one doesn't already exist - this user should be the admin too
      (user, company) <- runDB $ do
        company <- dbUpdate $ CreateCompany Nothing Nothing
        _ <- dbUpdate $ SetUserCompany (userid actvuser) (companyid company)
        _ <- dbUpdate $ MakeUserCompanyAdmin (userid actvuser)
        Just user <- dbQuery $ GetUserByID $ userid actvuser
        return (user, company)
      finalizeCompanyActivation user company
  where
    returnToAccountSetup :: Kontrakcja n => User -> Maybe Company -> n (Maybe User)
    returnToAccountSetup user mcompany = do
      addFlashM $ modalAccountSetup (Just user) mcompany $ LinkAccountCreated aid hash $ BS.toString $ getEmail user
      return Nothing

    asValidAccountType :: String -> Result Bool
    asValidAccountType "CompanyAccount" = return True
    asValidAccountType _ = return False

    finalizePrivateActivation :: Kontrakcja n => User -> n (Maybe User)
    finalizePrivateActivation user =
      finalizeActivation user Nothing id id
          
    finalizeCompanyActivation :: Kontrakcja n => User -> Company -> n (Maybe User)
    finalizeCompanyActivation user company = do
      -- is this from the acceptaccount after signup modal? if it is then they just type in their
      -- password, so we don't want to check for the user and company info stuff
      acceptaccount <- isFieldSet "acceptaccount"
      muserf <- if not acceptaccount
                  then getUserInfoUpdateFunc user
                  else return $ Just id
      mcompanyf <- if not acceptaccount && useriscompanyadmin user
                     then getCompanyInfoUpdateFunc company
                     else return $ Just id
      case (muserf, mcompanyf) of
        (Just userf, Just companyf) ->
          finalizeActivation user (Just company) userf companyf
        _ -> returnToAccountSetup user (Just company)

    finalizeActivation :: Kontrakcja n => User
                                          -> Maybe Company
                                          -> (UserInfo -> UserInfo)
                                          -> (CompanyInfo -> CompanyInfo)
                                          -> n (Maybe User)
    finalizeActivation user mcompany userinfoupdatefunc companyinfoupdatefunc = do
      mnewuser <- performActivation user mcompany aid userinfoupdatefunc companyinfoupdatefunc
      case mnewuser of
        Just newuser -> do
          addFlashM flashMessageUserActivated
          return $ Just newuser
        Nothing -> do
          -- performActivation might have updated user or company info, so we
          -- need to query database for the newest user & company version
          newuser <- fromMaybe user <$> (runDBQuery $ GetUserByID $ userid user)
          mnewcompany <- getCompanyForUser newuser
          returnToAccountSetup newuser mnewcompany

    getUserInfoUpdateFunc :: Kontrakcja n => User -> n (Maybe (UserInfo -> UserInfo))
    getUserInfoUpdateFunc _user = do
      mfname <- getRequiredField asValidName "fname"
      mlname <- getRequiredField asValidName "lname"
      mcompanyposition <- getRequiredField asValidPosition "companyposition"
      mphone <- getRequiredField (Good . BS.fromString) "phone"
      return $ 
        case (mfname, mlname, mcompanyposition, mphone) of
          (Just fname, Just lname, Just companytitle, Just phone) -> Just $ 
            \info -> info { userfstname = fname
                          , usersndname = lname
                          , usercompanyposition = companytitle
                          , userphone = phone
                          }
          _ -> Nothing
 
    getCompanyInfoUpdateFunc :: Kontrakcja n => Company -> n (Maybe (CompanyInfo -> CompanyInfo))
    getCompanyInfoUpdateFunc _company = do
      mcompanyname <- getRequiredField asValidCompanyName "companyname"
      return $ 
        case mcompanyname of
          (Just companyname') -> Just $ \info -> info { companyname = companyname' }
          _ -> Nothing
    
    performActivation :: Kontrakcja n => User
                                         -> Maybe Company
                                         -> ActionID
                                         -> (UserInfo -> UserInfo)
                                         -> (CompanyInfo -> CompanyInfo)
                                         -> n (Maybe User)
    performActivation user mcompany actionid userinfoupdatefunc companyinfoupdatefunc = do
      ctx <- getContext
      mtos <- getDefaultedField False asValidCheckBox "tos"
      mpassword <- getRequiredField asValidPassword "password"
      mpassword2 <- getRequiredField asValidPassword "password2"
      -- update user info he typed on signup page, so he won't
      -- have to type in again if password validation fails.
      _ <- runDBUpdate $ SetUserInfo (userid user) $ userinfoupdatefunc (userinfo user)
      -- if appropriate update the company info too
      if (isJust mcompany && useriscompanyadmin user && usercompany user == fmap companyid mcompany)
        then do
          let Just company = mcompany
          _ <- runDBUpdate $ SetCompanyInfo (companyid company) $ companyinfoupdatefunc (companyinfo company)
          return ()
        else return ()
      case (mtos, mpassword, mpassword2) of
        (Just tos, Just password, Just password2) -> do
          case checkPasswordsMatch password password2 of
            Right () ->
              if tos
                then do
                  passwordhash <- liftIO $ createPassword password
                  runDB $ do
                    _ <- dbUpdate $ SetUserPassword (userid user) passwordhash
                    _ <- dbUpdate $ AcceptTermsOfService (userid user) (ctxtime ctx)
                    _ <- dbUpdate $ SetSignupMethod (userid user) signupmethod
                    return ()
                  dropExistingAction actionid
                  logUserToContext $ Just user
                  return $ Just user
                else do
                  addFlashM flashMessageMustAcceptTOS
                  return Nothing
            Left flash -> do
              addFlashM flash
              return Nothing
        _ -> return Nothing


{- |
    This is where we get to when the user clicks the link in their password reminder
    email.  This'll show them the usual landing page, but with a modal dialog
    for changing their password.
-}
handlePasswordReminderGet :: Kontrakcja m => ActionID -> MagicHash -> m Response
handlePasswordReminderGet aid hash = do
    muser <- getUserFromActionOfType PasswordReminderID aid hash
    case muser of
         Just _ -> do
             extendActionEvalTimeToOneDayMinimum aid
             addFlashM $ modalNewPasswordView aid hash
             sendRedirect LinkUpload
         Nothing -> do
             addFlashM flashMessagePasswordChangeLinkNotValid
             linkmain <- getHomeOrUploadLink
             sendRedirect linkmain

handlePasswordReminderPost :: Kontrakcja m => ActionID -> MagicHash -> m KontraLink
handlePasswordReminderPost aid hash = do
    muser <- getUserFromActionOfType PasswordReminderID aid hash
    case muser of
         Just user -> handleChangePassword user
         Nothing   -> do
             addFlashM flashMessagePasswordChangeLinkNotValid
             getHomeOrUploadLink
    where
        handleChangePassword user = do
            mpassword <- getRequiredField asValidPassword "password"
            mpassword2 <- getRequiredField asDirtyPassword "password2"
            case (mpassword, mpassword2) of
                 (Just password, Just password2) -> do
                     case (checkPasswordsMatch password password2) of
                          Right () -> do
                              dropExistingAction aid
                              passwordhash <- liftIO $ createPassword password
                              _ <- runDBUpdate $ SetUserPassword (userid user) passwordhash
                              addFlashM flashMessageUserPasswordChanged
                              logUserToContext $ Just user
                              return LinkUpload
                          Left flash -> do
                              addFlashM flash
                              addFlashM $ modalNewPasswordView aid hash
                              getHomeOrUploadLink
                 _ -> do
                   addFlashM $ modalNewPasswordView aid hash
                   getHomeOrUploadLink

handleAccountRemovalGet :: Kontrakcja m => ActionID -> MagicHash -> m Response
handleAccountRemovalGet aid hash = do
  action <- guardJustM $ getAccountCreatedBySigningIDAction aid
  let AccountCreatedBySigning _ _ (docid, sigid) token = actionType action
  guard $ hash == token
  doc <- queryOrFail $ GetDocumentByDocumentID docid
  sig <- guardJust $ getSigLinkFor doc sigid
  extendActionEvalTimeToOneDayMinimum aid
  addFlashM $ modalAccountRemoval (documenttitle doc) (LinkAccountCreatedBySigning aid hash) (LinkAccountRemoval aid hash)
  sendRedirect $ LinkSignDoc doc sig

handleAccountRemovalFromSign :: Kontrakcja m => ActionID -> MagicHash -> m ()
handleAccountRemovalFromSign aid hash = do
  _doc <- handleAccountRemoval' aid hash
  return ()

handleAccountRemovalPost :: Kontrakcja m => ActionID -> MagicHash -> m KontraLink
handleAccountRemovalPost aid hash = do
  doc <- handleAccountRemoval' aid hash
  addFlashM $ modalAccountRemoved $ documenttitle doc
  getHomeOrUploadLink

{- |
    Helper function for performing account removal (these are accounts setup
    by signing), this'll return the document that was removed.
-}
handleAccountRemoval' :: Kontrakcja m => ActionID -> MagicHash -> m Document
handleAccountRemoval' aid hash = do
  action <- guardJustM $ getAccountCreatedBySigningIDAction aid        
  let AccountCreatedBySigning _ _ (docid, _) token = actionType action
  guard $ hash == token
  doc <- queryOrFail $ GetDocumentByDocumentID docid
  -- there should be done account and its documents removal, but
  -- since the functionality is not there yet, we just remove
  -- this action to prevent user from account activation and
  -- receiving further reminders
  dropExistingAction aid
  return doc

getAccountCreatedBySigningIDAction :: Kontrakcja m => ActionID -> m (Maybe Action)
getAccountCreatedBySigningIDAction aid = do
  maction <- query $ GetAction aid
  case maction of
    Nothing -> return Nothing
    Just action -> 
      -- allow for account created by signing links only
      if actionTypeID (actionType action) /= AccountCreatedBySigningID
      then return Nothing
      else if acbsState (actionType action) /= ReminderSent
           then return $ Just action
           else do
             now <- liftIO $ getMinutesTime
             return $ checkValidity now $ Just action

getUserFromActionOfType :: Kontrakcja m => ActionTypeID -> ActionID -> MagicHash -> m (Maybe User)
getUserFromActionOfType atypeid aid hash = do
    now <- liftIO $ getMinutesTime
    maction <- checkValidity now <$> query (GetAction aid)
    case maction of
         Just action -> do
             if atypeid == (actionTypeID $ actionType action)
                then getUID action >>= maybe
                         (return Nothing)
                         (runDBQuery . GetUserByID)
                else return Nothing
         Nothing -> return Nothing
    where
        getUID action =
            case actionType action of
                 PasswordReminder uid _ token -> verifyToken token uid
                 AccountCreated uid token     -> verifyToken token uid
                 _                            -> return Nothing
        verifyToken token uid = return $
            if hash == token
               then Just uid
               else Nothing

-- | Postpone link removal. Needed to make sure that between
-- GET and POST requests action won't be removed from the system.
extendActionEvalTimeToOneDayMinimum :: Kontrakcja m => ActionID -> m ()
extendActionEvalTimeToOneDayMinimum aid = do
    dayAfterNow <- minutesAfter (60*24) <$> liftIO getMinutesTime
    maction <- checkValidity dayAfterNow <$> query (GetAction aid)
    when_ (isNothing maction) $
        update $ UpdateActionEvalTime aid dayAfterNow

dropExistingAction :: Kontrakcja m => ActionID -> m ()
dropExistingAction aid = do
  _ <- update $ DeleteAction aid
  return ()
  
handleFriends :: Kontrakcja m => m JSValue
handleFriends = do
  Context{ctxmaybeuser} <- getContext
  user <- guardJust ctxmaybeuser
  friends <- runDBQuery $ GetUserFriends $ userid user
  params <- getListParamsNew
  let friendsPage = friendSortSearchPage params friends
  return $ JSObject $ toJSObject [("list", 
                                   JSArray $ 
                                   map (\f -> JSObject $ 
                                              toJSObject [("fields",
                                                           JSObject $ toJSObject [("email", 
                                                                                   JSString $ toJSString $ BS.toString $ getEmail f)
                                                                                 ,("id", JSString $ toJSString (show (userid f)))])])
                                           (list friendsPage)),
                                  ("paging", pagingParamsJSON friendsPage)]

handleCompanyAccounts :: Kontrakcja m => m JSValue
handleCompanyAccounts = withCompanyAdmin $ \companyid -> do
  Context{ctxmaybeuser = Just user} <- getContext
  companyaccounts' <- runDBQuery $ GetCompanyAccounts $ companyid
  -- filter out the current user, they don't want to see themselves in the list
  let companyaccounts = filter (not . (== userid user) . userid) companyaccounts'
  params <- getListParamsNew
  let companypage = companyAccountsSortSearchPage params companyaccounts
  return $ JSObject $ toJSObject [("list",
                                   JSArray $
                                   map (\f -> JSObject $
                                              toJSObject [("fields",
                                                           JSObject $ toJSObject [("id", 
                                                                                   JSString $ toJSString $ show $ userid f)
                                                                                 ,("firstname",
                                                                                   JSString $ toJSString $ BS.toString $ getFirstName f)
                                                                                 ,("lastname",
                                                                                   JSString $ toJSString $ BS.toString $ getLastName f)
                                                                                 ,("position",
                                                                                   JSString $ toJSString $ BS.toString $ usercompanyposition $ userinfo f)
                                                                                 ,("phone",
                                                                                   JSString $ toJSString $ BS.toString $ userphone $ userinfo f) 
                                                                                 ,("email",
                                                                                   JSString $ toJSString $ BS.toString $ getEmail f)])])
                                   (list companypage))
                                 ,("paging", pagingParamsJSON companypage)]
  

{- | 
   Fetch the xtoken param and double read it. Once as String and once as MagicHash.
 -}
readXToken :: Kontrakcja m => m (Either String MagicHash)
readXToken = do
  mxtoken <- join <$> (fmap maybeRead) <$> readField "xtoken"
  return $ maybe (Left $ "xtoken read failure" ) Right mxtoken

guardXToken :: Kontrakcja m => m ()
guardXToken = do
  Context { ctxxtoken } <- getContext
  xtoken <- guardRightM readXToken
  unless (xtoken == ctxxtoken) $ do
    Log.debug $ "xtoken failure: session: " ++ show ctxxtoken
      ++ " param: " ++ show xtoken
    mzero
