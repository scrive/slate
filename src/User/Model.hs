{-# OPTIONS_GHC -fno-warn-orphans -fcontext-stack=50 #-}
module User.Model (
    module User.Lang
  , module User.Region
  , module User.Locale
  , module User.Password
  , module User.UserID
  , Email(..)
  , DesignMode(..)
  , InviteType(..)
  , SignupMethod(..)
  , InviteInfo(..)
  , User(..)
  , UserInfo(..)
  , UserMailAPI(..)
  , UserSettings(..)
  , GetUsers(..)
  , GetUserByID(..)
  , GetUserByEmail(..)
  , GetCompanyAccounts(..)
  , GetInviteInfo(..)
  , GetUserMailAPI(..)
  , ExportUsersDetailsToCSV(..)
  , SetUserCompany(..)
  , DeleteUser(..)
  , AddUser(..)
  , SetUserEmail(..)
  , SetUserPassword(..)
  , SetInviteInfo(..)
  , SetUserMailAPI(..)
  , SetUserInfo(..)
  , SetUserSettings(..)
  , SetPreferredDesignMode(..)
  , AcceptTermsOfService(..)
  , SetSignupMethod(..)
  , SetUserCompanyAdmin(..)
  , composeFullName
  ) where

import Control.Applicative
import Data.Data
import Data.Int
import Database.HDBC
import Happstack.State
import qualified Control.Exception as E
import qualified Data.ByteString.Char8 as BS

import API.Service.Model
import Company.Model
import DB.Classes
import DB.Derive
import DB.Fetcher2
import DB.Types
import DB.Utils
import MinutesTime
import User.Lang
import User.Locale
import User.Password
import User.Region
import User.Tables
import User.UserID

-- newtypes
newtype Email = Email { unEmail :: BS.ByteString }
  deriving (Eq, Ord)
$(newtypeDeriveConvertible ''Email)
$(newtypeDeriveUnderlyingReadShow ''Email)

-- enums
data DesignMode = BasicMode | AdvancedMode
  deriving (Eq, Ord, Show)
$(enumDeriveConvertible ''DesignMode)

data InviteType = Viral | Admin
  deriving (Eq, Ord, Show)
$(enumDeriveConvertible ''InviteType)

data SignupMethod = AccountRequest | ViralInvitation | BySigning
  deriving (Eq, Ord, Show)
$(enumDeriveConvertible ''SignupMethod)

-- data structures
data InviteInfo = InviteInfo {
    userinviter :: UserID
  , invitetime  :: Maybe MinutesTime
  , invitetype  :: Maybe InviteType
  } deriving (Eq, Ord, Show)

data User = User {
    userid                        :: UserID
  , userpassword                  :: Maybe Password
  , useriscompanyadmin            :: Bool
  , useraccountsuspended          :: Bool
  , userhasacceptedtermsofservice :: Maybe MinutesTime
  , usersignupmethod              :: SignupMethod
  , userinfo                      :: UserInfo
  , usersettings                  :: UserSettings
  , userservice                   :: Maybe ServiceID
  , usercompany                   :: Maybe CompanyID
  } deriving (Eq, Ord, Show)

data UserInfo = UserInfo {
    userfstname         :: BS.ByteString
  , usersndname         :: BS.ByteString
  , userpersonalnumber  :: BS.ByteString
  , usercompanyposition :: BS.ByteString
  , userphone           :: BS.ByteString
  , usermobile          :: BS.ByteString
  , useremail           :: Email
  } deriving (Eq, Ord, Show)

data UserMailAPI = UserMailAPI {
    umapiKey          :: MagicHash
  , umapiDailyLimit   :: Int32
  , umapiSentToday    :: Int32
  } deriving (Eq, Ord, Show)

data UserSettings  = UserSettings {
    preferreddesignmode :: Maybe DesignMode
  , locale              :: Locale
  , customfooter        :: Maybe String
  } deriving (Eq, Ord, Show)

instance HasLocale User where
  getLocale = getLocale . usersettings

instance HasLocale UserSettings where
  getLocale = locale

data GetUsers = GetUsers
instance DBQuery GetUsers [User] where
  dbQuery GetUsers = do
    kPrepare $ selectUsersSQL ++ " WHERE u.deleted = FALSE ORDER BY u.first_name || ' ' || u.last_name DESC"
    _ <- kExecute []
    fetchUsers

data GetUserByID = GetUserByID UserID
instance DBQuery GetUserByID (Maybe User) where
  dbQuery (GetUserByID uid) = do
    kPrepare $ selectUsersSQL ++ " WHERE u.id = ? AND u.deleted = FALSE"
    _ <- kExecute [toSql uid]
    fetchUsers >>= oneObjectReturnedGuard

data GetUserByEmail = GetUserByEmail (Maybe ServiceID) Email
instance DBQuery GetUserByEmail (Maybe User) where
  dbQuery (GetUserByEmail msid email) = do
    kPrepare $ selectUsersSQL ++ " WHERE u.deleted = FALSE AND u.service_id IS NOT DISTINCT FROM ? AND u.email = ?"
    _ <- kExecute [toSql msid, toSql email]
    fetchUsers >>= oneObjectReturnedGuard

data GetCompanyAccounts = GetCompanyAccounts CompanyID
instance DBQuery GetCompanyAccounts [User] where
  dbQuery (GetCompanyAccounts cid) = do
    kPrepare $ selectUsersSQL ++ " WHERE u.company_id = ? AND u.deleted = FALSE ORDER BY u.email DESC"
    _ <- kExecute [toSql cid]
    fetchUsers

data GetInviteInfo = GetInviteInfo UserID
instance DBQuery GetInviteInfo (Maybe InviteInfo) where
  dbQuery (GetInviteInfo uid) = do
    kPrepare "SELECT inviter_id, invite_time, invite_type FROM user_invite_infos WHERE user_id = ?"
    _ <- kExecute [toSql uid]
    foldDB fetchInviteInfos [] >>= oneObjectReturnedGuard
    where
      fetchInviteInfos acc inviter_id invite_time invite_type = InviteInfo {
          userinviter = inviter_id
        , invitetime = invite_time
        , invitetype = invite_type
        } : acc

data GetUserMailAPI = GetUserMailAPI UserID
instance DBQuery GetUserMailAPI (Maybe UserMailAPI) where
  dbQuery (GetUserMailAPI uid) = do
    kPrepare "SELECT key, daily_limit, (CASE WHEN last_sent_date = now()::DATE THEN sent_today ELSE 0 END) FROM user_mail_apis WHERE user_id = ?"
    _ <- kExecute [toSql uid]
    foldDB fetchUserMailAPIs [] >>= oneObjectReturnedGuard
    where
      fetchUserMailAPIs acc key daily_limit sent_today = UserMailAPI {
          umapiKey = key
        , umapiDailyLimit = daily_limit
        , umapiSentToday = sent_today
        } : acc

data ExportUsersDetailsToCSV = ExportUsersDetailsToCSV
instance DBQuery ExportUsersDetailsToCSV BS.ByteString where
  dbQuery ExportUsersDetailsToCSV = do
    kQuickQuery "SELECT first_name || ' ' || last_name, email FROM users WHERE deleted = FALSE" []
      >>= return . toCSV
    where
      toCSV = BS.unlines . map (BS.intercalate (BS.pack ", ") . map fromSql)

data SetUserCompany = SetUserCompany UserID (Maybe CompanyID)
instance DBUpdate SetUserCompany Bool where
  dbUpdate (SetUserCompany uid mcid) = case mcid of
    Nothing -> do
      kPrepare "UPDATE users SET company_id = NULL, is_company_admin = FALSE WHERE id = ? AND deleted = FALSE"
      kExecute01 [toSql uid]
    Just cid -> do
      kPrepare "UPDATE users SET company_id = ? WHERE id = ? AND deleted = FALSE"
      kExecute01 [toSql cid, toSql uid]

-- | Marks a user as deleted so that queries won't return them any more.
-- TODO: change deleted to time
data DeleteUser = DeleteUser UserID
instance DBUpdate DeleteUser Bool where
  dbUpdate (DeleteUser uid) = do
    kPrepare $ "UPDATE users SET deleted = ? WHERE id = ? AND deleted = FALSE"
    kExecute01 [toSql True, toSql uid]

-- | TODO: Fix this AddUser, it shouldn't lock.
data AddUser = AddUser (BS.ByteString, BS.ByteString) BS.ByteString (Maybe Password) Bool (Maybe ServiceID) (Maybe CompanyID) Locale
instance DBUpdate AddUser (Maybe User) where
  dbUpdate (AddUser (fname, lname) email mpwd iscompadmin msid mcid l) = do
    let handle e = case e of
          NoObject{} -> return Nothing
          _ -> E.throw e
    _ <- kRunRaw "LOCK TABLE users IN ACCESS EXCLUSIVE MODE"
    mu <- dbQuery (GetUserByEmail msid $ Email email) `catchDB` handle
    case mu of
      Just _ -> return Nothing -- user with the same email address exists
      Nothing -> do
        uid <- UserID <$> getUniqueID tableUsers
        kPrepare $ "INSERT INTO users ("
          ++ "  id"
          ++ ", password"
          ++ ", salt"
          ++ ", is_company_admin"
          ++ ", account_suspended"
          ++ ", has_accepted_terms_of_service"
          ++ ", signup_method"
          ++ ", service_id"
          ++ ", company_id"
          ++ ", first_name"
          ++ ", last_name"
          ++ ", personal_number"
          ++ ", company_position"
          ++ ", phone"
          ++ ", mobile"
          ++ ", email"
          ++ ", preferred_design_mode"
          ++ ", lang"
          ++ ", region"
          ++ ", deleted) VALUES (?, decode(?, 'base64'), decode(?, 'base64'), ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
        _ <- kExecute $ [
            toSql uid
          , toSql $ pwdHash <$> mpwd
          , toSql $ pwdSalt <$> mpwd
          , toSql iscompadmin
          , toSql False
          , SqlNull
          , toSql AccountRequest
          , toSql msid
          , toSql mcid
          , toSql fname
          , toSql lname
          ] ++ replicate 4 (toSql "")
            ++ [toSql email] ++ [
              SqlNull
            , toSql $ getLang l
            , toSql $ getRegion l
            , toSql False
            ]
        dbQuery $ GetUserByID uid

data SetUserEmail = SetUserEmail (Maybe ServiceID) UserID Email
instance DBUpdate SetUserEmail Bool where
  dbUpdate (SetUserEmail msid uid email) = do
    kPrepare $ "UPDATE users SET email = ?"
      ++ " WHERE id = ? AND deleted = FALSE AND service_id IS NOT DISTINCT FROM ?"
    kExecute01 [toSql email, toSql uid, toSql msid]

data SetUserPassword = SetUserPassword UserID Password
instance DBUpdate SetUserPassword Bool where
  dbUpdate (SetUserPassword uid pwd) = do
    kPrepare $ "UPDATE users SET"
      ++ "  password = decode(?, 'base64')"
      ++ ", salt = decode(?, 'base64')"
      ++ "  WHERE id = ? AND deleted = FALSE"
    kExecute01 [toSql $ pwdHash pwd, toSql $ pwdSalt pwd, toSql uid]

data SetInviteInfo = SetInviteInfo (Maybe UserID) MinutesTime InviteType UserID
instance DBUpdate SetInviteInfo Bool where
  dbUpdate (SetInviteInfo minviterid invitetime invitetype uid) = do
    exists <- checkIfUserExists uid
    if exists
      then do
        case minviterid of
          Just inviterid -> do
            _ <- kRunRaw "LOCK TABLE user_invite_infos IN ACCESS EXCLUSIVE MODE"
            rec_exists <- kQuickQuery "SELECT 1 FROM user_invite_infos WHERE user_id = ?" [toSql uid]
              >>= checkIfOneObjectReturned
            if rec_exists
              then do
                kPrepare $ "UPDATE user_invite_infos SET"
                  ++ "  inviter_id = ?"
                  ++ ", invite_time = ?"
                  ++ ", invite_type = ?"
                  ++ "  WHERE user_id = ?"
                kExecute01 [
                    toSql inviterid
                  , toSql invitetime
                  , toSql invitetype
                  , toSql uid
                  ]
              else do
                kPrepare $ "INSERT INTO user_invite_infos ("
                  ++ "  user_id"
                  ++ ", inviter_id"
                  ++ ", invite_time"
                  ++ ", invite_type) VALUES (?, ?, ?, ?)"
                kExecute01 [
                    toSql uid
                  , toSql inviterid
                  , toSql invitetime
                  , toSql invitetype
                  ]
          Nothing -> do
            kPrepare "DELETE FROM user_invite_infos WHERE user_id = ?"
            kExecute01 [toSql uid]
      else return False

data SetUserMailAPI = SetUserMailAPI UserID (Maybe UserMailAPI)
instance DBUpdate SetUserMailAPI Bool where
  dbUpdate (SetUserMailAPI uid musermailapi) = do
    exists <- checkIfUserExists uid
    if exists
      then case musermailapi of
        Just mailapi -> do
          _ <- kRunRaw "LOCK TABLE user_mail_apis IN ACCESS EXCLUSIVE MODE"
          rec_exists <- kQuickQuery "SELECT 1 FROM user_mail_apis WHERE user_id = ?" [toSql uid]
              >>= checkIfOneObjectReturned
          if rec_exists
            then do
              kPrepare $ "UPDATE user_mail_apis SET"
                  ++ "  key = ?"
                  ++ ", daily_limit = ?"
                  ++ ", sent_today = ?"
                  ++ ", last_sent_date = now()"
                  ++ "  WHERE user_id = ?"
              kExecute01 [
                  toSql $ umapiKey mailapi
                , toSql $ umapiDailyLimit mailapi
                , toSql $ umapiSentToday mailapi
                , toSql uid
                ]
            else do
              kPrepare $ "INSERT INTO user_mail_apis ("
                ++ "  user_id"
                ++ ", key"
                ++ ", daily_limit"
                ++ ", sent_today"
                ++ ", last_sent_date) VALUES (?, ?, ?, ?, now())"
              kExecute01 [
                  toSql uid
                , toSql $ umapiKey mailapi
                , toSql $ umapiDailyLimit mailapi
                , toSql $ umapiSentToday mailapi
                ]
        Nothing -> do
          kPrepare "DELETE FROM user_mail_apis WHERE user_id = ?"
          kExecute01 [toSql uid]
      else return False

data SetUserInfo = SetUserInfo UserID UserInfo
instance DBUpdate SetUserInfo Bool where
  dbUpdate (SetUserInfo uid info) = do
    kPrepare $ "UPDATE users SET"
      ++ "  first_name = ?"
      ++ ", last_name = ?"
      ++ ", personal_number = ?"
      ++ ", company_position = ?"
      ++ ", phone = ?"
      ++ ", mobile = ?"
      ++ ", email = ?"
      ++ "  WHERE id = ? AND deleted = FALSE"
    kExecute01 [
        toSql $ userfstname info
      , toSql $ usersndname info
      , toSql $ userpersonalnumber info
      , toSql $ usercompanyposition info
      , toSql $ userphone info
      , toSql $ usermobile info
      , toSql $ useremail info
      , toSql uid
      ]

data SetUserSettings = SetUserSettings UserID UserSettings
instance DBUpdate SetUserSettings Bool where
  dbUpdate (SetUserSettings uid us) = do
    kPrepare $ "UPDATE users SET"
      ++ "  preferred_design_mode = ?"
      ++ ", lang = ?"
      ++ ", region = ?"
      ++ ", customfooter = ?"
      ++ "  WHERE id = ? AND deleted = FALSE"
    kExecute01 [
        toSql $ preferreddesignmode us
      , toSql $ getLang us
      , toSql $ getRegion us
      , toSql $ customfooter us
      , toSql uid
      ]

data SetPreferredDesignMode = SetPreferredDesignMode UserID (Maybe DesignMode)
instance DBUpdate SetPreferredDesignMode Bool where
  dbUpdate (SetPreferredDesignMode uid mmode) = do
    kPrepare $ "UPDATE users SET preferred_design_mode = ? WHERE id = ? AND deleted = FALSE"
    kExecute01 [toSql mmode, toSql uid]

data AcceptTermsOfService = AcceptTermsOfService UserID MinutesTime
instance DBUpdate AcceptTermsOfService Bool where
  dbUpdate (AcceptTermsOfService uid time) = do
    kPrepare $ "UPDATE users SET"
      ++ "  has_accepted_terms_of_service = ?"
      ++ "  WHERE id = ? AND deleted = FALSE"
    kExecute01 [
        toSql time
      , toSql uid
      ]

data SetSignupMethod = SetSignupMethod UserID SignupMethod
instance DBUpdate SetSignupMethod Bool where
  dbUpdate (SetSignupMethod uid signupmethod) = do
    kPrepare "UPDATE users SET signup_method = ? WHERE id = ? AND deleted = FALSE"
    kExecute01 [toSql signupmethod, toSql uid]

data SetUserCompanyAdmin = SetUserCompanyAdmin UserID Bool
instance DBUpdate SetUserCompanyAdmin Bool where
  dbUpdate (SetUserCompanyAdmin uid iscompanyadmin) = do
    mcid <- getOne "SELECT company_id FROM users WHERE id = ? AND deleted = FALSE FOR UPDATE" [toSql uid]
    case mcid :: Maybe CompanyID of
      Nothing -> return False
      Just _ -> wrapDB $ \conn -> do
        r <- run conn "UPDATE users SET is_company_admin = ? WHERE id = ? AND deleted = FALSE" [toSql iscompanyadmin, toSql uid]
        oneRowAffectedGuard r

-- helpers

composeFullName :: (BS.ByteString, BS.ByteString) -> BS.ByteString
composeFullName (fstname, sndname) =
    if BS.null sndname
       then fstname
       else fstname `BS.append` BS.pack " " `BS.append` sndname

checkIfUserExists :: UserID -> DB Bool
checkIfUserExists uid = do
  kQuickQuery "SELECT 1 FROM users WHERE id = ? AND deleted = FALSE" [toSql uid]
    >>= checkIfOneObjectReturned

selectUsersSQL :: String
selectUsersSQL = "SELECT "
 ++ "  u.id"
 ++ ", encode(u.password, 'base64')"
 ++ ", encode(u.salt, 'base64')"
 ++ ", u.is_company_admin"
 ++ ", u.account_suspended"
 ++ ", u.has_accepted_terms_of_service"
 ++ ", u.signup_method"
 ++ ", u.service_id"
 ++ ", u.company_id"
 ++ ", u.first_name"
 ++ ", u.last_name"
 ++ ", u.personal_number"
 ++ ", u.company_position"
 ++ ", u.phone"
 ++ ", u.mobile"
 ++ ", u.email"
 ++ ", u.preferred_design_mode"
 ++ ", u.lang"
 ++ ", u.region"
 ++ ", u.customfooter"
 ++ "  FROM users u"
 ++ " "

fetchUsers :: DB [User]
fetchUsers = foldDB decoder []
  where
    -- Note: this function gets users in reversed order, but all queries
    -- use ORDER BY DESC, so in the end everything is properly ordered.
    decoder acc uid password salt is_company_admin account_suspended
      has_accepted_terms_of_service signup_method service_id company_id
      first_name last_name personal_number company_position phone mobile
      email preferred_design_mode lang region customfooter = User {
          userid = uid
        , userpassword = maybePassword (password, salt)
        , useriscompanyadmin = is_company_admin
        , useraccountsuspended = account_suspended
        , userhasacceptedtermsofservice = has_accepted_terms_of_service
        , usersignupmethod = signup_method
        , userinfo = UserInfo {
            userfstname = first_name
          , usersndname = last_name
          , userpersonalnumber = personal_number
          , usercompanyposition = company_position
          , userphone = phone
          , usermobile = mobile
          , useremail = email
          }
        , usersettings = UserSettings {
            preferreddesignmode = preferred_design_mode
          , locale = mkLocale region lang
          , customfooter = customfooter
          }
        , userservice = service_id
        , usercompany = company_id
        } : acc

-- this will not be needed when we move documents to pgsql. for now it's needed
-- for document handlers - it seems that types of arguments that handlers take
-- need to be serializable. I don't know wtf, but I'll gladly dispose of these
-- instances when we're done with the migration.

deriving instance Typeable User
deriving instance Typeable UserSettings
deriving instance Typeable UserInfo
deriving instance Typeable SignupMethod
deriving instance Typeable Password
deriving instance Typeable Lang
deriving instance Typeable Region
deriving instance Typeable Locale
deriving instance Typeable DesignMode
deriving instance Typeable Email
deriving instance Typeable Binary

instance Version User
instance Version UserSettings
instance Version UserInfo
instance Version SignupMethod
instance Version Password
instance Version Lang
instance Version Region
instance Version Locale
instance Version DesignMode
instance Version Email
instance Version Binary

$(deriveSerializeFor [
    ''User
  , ''UserSettings
  , ''UserInfo
  , ''SignupMethod
  , ''Password
  , ''Lang
  , ''Region
  , ''Locale
  , ''DesignMode
  , ''Email
  , ''Binary
  ])
