{-# OPTIONS_GHC -Wall #-}
module User.UserState 
    ( Email(..)
    , Friend(..)
    , Inviter(..)
    , InviteType(..)
    , InviteInfo(..)
    , LoginInfo(..)
    , DefaultMainSignatory(..)
    , SignupMethod(..)
    , ExternalUserID(..)
    , Password(..)
    , TrustWeaverStorage(..)
    , UserAccountType(..)
    , PaymentMethod(..)
    , UserAccountPlan(..)
    , SupervisorID(..)
    , User(..)
    , UserInfo(..)
    , UserSettings(..)
    , DesignMode(..)
    , UserID(..)
    , Users
    , UserStats(..)
    , composeFullName
    , userfullname
    , isAbleToHaveSubaccounts

    , AcceptTermsOfService(..)
    , SetFreeTrialExpirationDate(..)
    , SetSignupMethod(..)
    , AddUser(..)
    , ExportUsersDetailsToCSV(..)
    , GetAllUsers(..)
    , GetUserByEmail(..)
    , GetUserByUserID(..)
    , GetUserStats(..)
    , GetUserStatsByUser(..)
    , GetUserSubaccounts(..)
    , GetUserRelatedAccounts(..)
    , GetUserFriends(..)
    , SetUserInfo(..)
    , SetInviteInfo(..)
    , SetUserSettings(..)
    , SetPreferredDesignMode(..)
    , SetUserPaymentAccount(..)
    , SetUserPaymentPolicyChange(..)
    , SetUserPassword(..)
    , SetUserSupervisor(..)
    , GetUsersByFriendUserID(..)
    , AddViewerByEmail(..)
    --, FreeUserFromPayments(..)
    --, AddFreePaymentsForInviter(..)
    , RecordFailedLogin(..)
    , RecordSuccessfulLogin(..)
    , getUserPaymentSchema
    , takeImmediatelyPayment
) where
import Happstack.Data
import Happstack.State
import Control.Monad
import Control.Monad.Reader (ask)
import Control.Monad.State (modify,MonadState(..))
import qualified Data.ByteString.UTF8 as BS
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BS (unlines) 
import Happstack.Data.IxSet as IxSet
import Data.Maybe(isJust,fromJust,maybe)
import Misc
import Happstack.Server.SimpleHTTP
import Happstack.Util.Common
import Codec.Utils (Octet)
import Data.Digest.SHA256 (hash)
import System.Random
import Data.List
import Data.Maybe (isNothing)
import qualified Data.Set as Set
import Control.Applicative
import System.Time as ST
import MinutesTime as MT
import Payments.PaymentsState as Payments
import Data.Data
import Data.Maybe
import User.Password
import API.Service.ServiceState 

newtype UserID = UserID { unUserID :: Int }
    deriving (Eq, Ord, Typeable)

deriving instance Data UserID

data SignupMethod = AccountRequest | ViralInvitation | BySigning
    deriving (Eq, Ord, Show, Typeable)

newtype ExternalUserID = ExternalUserID { unExternalUserID :: BS.ByteString }
    deriving (Eq, Ord, Typeable)
newtype Friend = Friend { unFriend :: Int }
    deriving (Eq, Ord, Typeable)
newtype Inviter = Inviter { unInviter :: Int }
    deriving (Eq, Ord, Typeable)
data InviteType = Viral | Admin
    deriving (Eq, Ord, Typeable)
data InviteInfo = InviteInfo 
          { userinviter :: Inviter
          , invitetime :: Maybe MinutesTime
          , invitetype :: Maybe InviteType
          }
    deriving (Eq, Ord, Typeable)
data LoginInfo = LoginInfo
          { lastsuccesstime :: Maybe MinutesTime
          , lastfailtime :: Maybe MinutesTime
          , consecutivefails :: Int
          }
    deriving (Eq, Ord, Typeable)
newtype DefaultMainSignatory = DefaultMainSignatory { unDMS :: Int }
    deriving (Eq, Ord, Typeable)
newtype Email = Email { unEmail :: BS.ByteString }
    deriving (Eq, Ord, Typeable)
newtype SupervisorID = SupervisorID { unSupervisorID :: Int }
    deriving (Eq, Ord, Typeable)
data TrustWeaverStorage = TrustWeaverStorage
          { storagetwenabled       :: Bool
          , storagetwname          :: BS.ByteString
          , storagetwsuperadmin    :: BS.ByteString
          , storagetwsuperadminpwd :: BS.ByteString
          , storagetwsectionpath   :: BS.ByteString
          }
    deriving (Eq, Ord, Typeable)

data UserAccountType0 = MainAccount | SubAccount
    deriving (Eq, Ord, Typeable)

data UserAccountType = PrivateAccount | CompanyAccount
    deriving (Eq, Ord, Typeable)

data PaymentMethod = CreditCard | Invoice | Undefined
    deriving (Eq, Ord, Typeable)

deriving instance Data PaymentMethod

data UserAccountPlan = Basic
    deriving (Eq, Ord, Typeable)
data UserInfo0 = UserInfo0 {
            userfstname0                   :: BS.ByteString
          , usersndname0                   :: BS.ByteString
          , userpersonalnumber0            :: BS.ByteString
          , usercompanyname0               :: BS.ByteString
          , usercompanynumber0             :: BS.ByteString
          , useraddress0                   :: BS.ByteString 
          , userzip0                       :: BS.ByteString
          , usercity0                      :: BS.ByteString
          , usercountry0                   :: BS.ByteString
          , userphone0                     :: BS.ByteString
          , usermobile0                    :: BS.ByteString
          , useremail0                     :: Email 
          }       
                 deriving (Eq, Ord, Typeable)
          
data UserInfo = UserInfo {
            userfstname                   :: BS.ByteString
          , usersndname                   :: BS.ByteString
          , userpersonalnumber            :: BS.ByteString
          , usercompanyname               :: BS.ByteString
          , usercompanyposition           :: BS.ByteString
          , usercompanynumber             :: BS.ByteString
          , useraddress                   :: BS.ByteString 
          , userzip                       :: BS.ByteString
          , usercity                      :: BS.ByteString
          , usercountry                   :: BS.ByteString
          , userphone                     :: BS.ByteString
          , usermobile                    :: BS.ByteString
          , useremail                     :: Email 
          }        
    deriving (Eq, Ord, Typeable)

data UserSettings0  = UserSettings0 {
               accounttype0 :: UserAccountType
             , accountplan0 :: UserAccountPlan
             , signeddocstorage0 :: Maybe TrustWeaverStorage
             , userpaymentmethod0 :: PaymentMethod
      }
    deriving (Eq, Ord, Typeable)

data UserSettings  = UserSettings {
               accounttype :: UserAccountType
             , accountplan :: UserAccountPlan
             , signeddocstorage :: Maybe TrustWeaverStorage
             , userpaymentmethod :: PaymentMethod
             , preferreddesignmode :: Maybe DesignMode
      }
    deriving (Eq, Ord, Typeable)

data DesignMode = BasicMode | AdvancedMode
    deriving (Eq, Ord, Typeable)

data User = User
          { userid                        :: UserID
          , userpassword                  :: Password
          , usersupervisor                :: Maybe SupervisorID
          , useraccountsuspended          :: Bool
          , userhasacceptedtermsofservice :: Maybe MinutesTime
          , userfreetrialexpirationdate   :: Maybe MinutesTime
          , usersignupmethod              :: SignupMethod
          , userinfo                      :: UserInfo
          , usersettings                  :: UserSettings
          , userpaymentpolicy             :: Payments.UserPaymentPolicy
          , userpaymentaccount            :: Payments.UserPaymentAccount
          , userfriends                   :: [Friend]
          , userinviteinfo                :: Maybe InviteInfo
          , userlogininfo                 :: LoginInfo
          , userservice                   :: Maybe ServiceID
          , userterminated                :: Bool
          }
            deriving (Eq, Ord)

instance Typeable User where typeOf _ = mkTypeOf "User"

data User12 = User12
          { userid12                        :: UserID
          , userpassword12                  :: Password
          , usersupervisor12                :: Maybe SupervisorID
          , useraccountsuspended12          :: Bool
          , userhasacceptedtermsofservice12 :: Maybe MinutesTime
          , userinfo12                      :: UserInfo
          , usersettings12                  :: UserSettings
          , userpaymentpolicy12             :: Payments.UserPaymentPolicy
          , userpaymentaccount12            :: Payments.UserPaymentAccount
          , userfriends12                   :: [Friend]
          , userinviteinfo12                :: Maybe InviteInfo
          , userlogininfo12                 :: LoginInfo
          }
            deriving (Eq, Ord, Typeable)

data User11 = User11
          { userid11                        :: UserID
          , userpassword11                  :: Password
          , usersupervisor11                :: Maybe SupervisorID
          , usercanhavesubaccounts11        :: Bool
          , useraccountsuspended11          :: Bool
          , userhasacceptedtermsofservice11 :: Maybe MinutesTime
          , userinfo11                      :: UserInfo
          , usersettings11                  :: UserSettings
          , userpaymentpolicy11             :: Payments.UserPaymentPolicy
          , userpaymentaccount11            :: Payments.UserPaymentAccount
          , userfriends11                   :: [Friend]
          , userinviteinfo11                :: Maybe InviteInfo
          , userlogininfo11                 :: LoginInfo
          }
    deriving (Eq, Ord, Typeable)

data User10 = User10
          { userid10                        :: UserID
          , userpassword10                  :: Password
          , usersupervisor10                :: Maybe SupervisorID
          , usercanhavesubaccounts10        :: Bool
          , useraccountsuspended10          :: Bool
          , userhasacceptedtermsofservice10 :: Maybe MinutesTime
          , userinfo10                      :: UserInfo
          , usersettings10                  :: UserSettings
          , userpaymentpolicy10             :: Payments.UserPaymentPolicy
          , userpaymentaccount10            :: Payments.UserPaymentAccount
          , userfriends10                   :: [Friend]
          , userinviteinfo10                :: Maybe InviteInfo
          }
    deriving (Eq, Ord, Typeable)

data User9 = User9
          { userid9                        :: UserID
          , userpassword9                  :: Password
          , usersupervisor9                :: Maybe SupervisorID
          , usercanhavesubaccounts9        :: Bool
          , useraccountsuspended9          :: Bool
          , userhasacceptedtermsofservice9 :: Maybe MinutesTime
          , userinfo9                      :: UserInfo
          , usersettings9                  :: UserSettings
          , userpaymentpolicy9             :: Payments.UserPaymentPolicy
          , userpaymentaccount9            :: Payments.UserPaymentAccount
          , userfriends9                   :: [Friend]
          , userinviter9                   :: Maybe Inviter
          }
    deriving (Eq, Ord, Typeable)
          
data User8 = User8
          { userid8                        :: UserID
          , userpassword8                  :: Password
          , usersupervisor8                :: Maybe SupervisorID
          , usercanhavesubaccounts8        :: Bool
          , useraccountsuspended8          :: Bool
          , userhasacceptedtermsofservice8 :: Maybe MinutesTime
          , userinfo8                      :: UserInfo
          , usersettings8                  :: UserSettings
          , userpaymentpolicy8             :: Payments.UserPaymentPolicy
          , userpaymentaccount8            :: Payments.UserPaymentAccount
          , userfriends8                   :: [Friend]
          -- should remove userdefaultmainsignatory in the next migration. just get rid of it.
          , userdefaultmainsignatory8      :: DefaultMainSignatory
          }
    deriving (Eq, Ord, Typeable)


data UserStats = UserStats 
                       { usercount :: Int
                       , viralinvitecount :: Int
                       , admininvitecount :: Int
                       }
    deriving (Eq, Ord, Typeable)

deriving instance Data UserStats

deriving instance Show TrustWeaverStorage
deriving instance Show UserAccountType 
deriving instance Show PaymentMethod
deriving instance Show UserAccountPlan 
deriving instance Show UserInfo
deriving instance Show UserSettings
deriving instance Show DesignMode
deriving instance Show User
deriving instance Show Email
deriving instance Show Friend
deriving instance Show Inviter
deriving instance Show InviteInfo
deriving instance Show InviteType
deriving instance Show LoginInfo
deriving instance Show DefaultMainSignatory
deriving instance Show UserStats

deriving instance Read TrustWeaverStorage

deriving instance Bounded UserAccountType
deriving instance Enum UserAccountType
deriving instance Read UserAccountType

deriving instance Bounded PaymentMethod
deriving instance Enum PaymentMethod
deriving instance Read PaymentMethod

deriving instance Bounded UserAccountPlan
deriving instance Enum UserAccountPlan
deriving instance Read UserAccountPlan

instance Migrate UserAccountType0 UserAccountType where
    migrate _ = PrivateAccount

instance Migrate () User8 where
    migrate () = error "Cannot migrate to User8"

instance Migrate User8 User9 where
    migrate (User8
               { userid8                     
                , userpassword8                
                , usersupervisor8               
                , usercanhavesubaccounts8        
                , useraccountsuspended8          
                , userhasacceptedtermsofservice8  
                , userinfo8                     
                , usersettings8                
                , userpaymentpolicy8             
                , userpaymentaccount8           
                , userfriends8                  
                , userdefaultmainsignatory8 = _       
                }) = User9 
                { userid9                         = userid8
                , userpassword9                   = userpassword8
                , usersupervisor9                 = usersupervisor8
                , usercanhavesubaccounts9         = usercanhavesubaccounts8
                , useraccountsuspended9           = useraccountsuspended8
                , userhasacceptedtermsofservice9  = userhasacceptedtermsofservice8
                , userinfo9                       = userinfo8
                , usersettings9                   = usersettings8
                , userpaymentpolicy9              = userpaymentpolicy8
                , userpaymentaccount9             = userpaymentaccount8
                , userfriends9                    = userfriends8
                , userinviter9                    = Nothing          
                }

instance Migrate User9 User10 where
    migrate (User9
               { userid9                     
                , userpassword9                
                , usersupervisor9               
                , usercanhavesubaccounts9        
                , useraccountsuspended9          
                , userhasacceptedtermsofservice9  
                , userinfo9                     
                , usersettings9                
                , userpaymentpolicy9             
                , userpaymentaccount9           
                , userfriends9                  
                , userinviter9       
                }) = User10 
                { userid10                         = userid9
                , userpassword10                   = userpassword9
                , usersupervisor10                 = usersupervisor9
                , usercanhavesubaccounts10         = usercanhavesubaccounts9
                , useraccountsuspended10           = useraccountsuspended9
                , userhasacceptedtermsofservice10  = userhasacceptedtermsofservice9
                , userinfo10                       = userinfo9
                , usersettings10                   = usersettings9
                , userpaymentpolicy10              = userpaymentpolicy9
                , userpaymentaccount10             = userpaymentaccount9
                , userfriends10                    = userfriends9
                , userinviteinfo10                 = fmap 
                                                       (\inviter ->  InviteInfo
                                                           { userinviter = inviter
                                                           , invitetime = Nothing
                                                           , invitetype = Nothing
                                                       })
                                                       userinviter9
                }

instance Migrate User10 User11 where
    migrate (User10
               { userid10                     
                , userpassword10                
                , usersupervisor10               
                , usercanhavesubaccounts10        
                , useraccountsuspended10          
                , userhasacceptedtermsofservice10  
                , userinfo10                     
                , usersettings10                
                , userpaymentpolicy10             
                , userpaymentaccount10           
                , userfriends10                  
                , userinviteinfo10       
                }) = User11 
                { userid11                         = userid10
                , userpassword11                   = userpassword10
                , usersupervisor11                 = usersupervisor10
                , usercanhavesubaccounts11         = usercanhavesubaccounts10
                , useraccountsuspended11           = useraccountsuspended10
                , userhasacceptedtermsofservice11  = userhasacceptedtermsofservice10
                , userinfo11                       = userinfo10
                , usersettings11                   = usersettings10
                , userpaymentpolicy11              = userpaymentpolicy10
                , userpaymentaccount11             = userpaymentaccount10
                , userfriends11                    = userfriends10
                , userinviteinfo11                 = userinviteinfo10
                , userlogininfo11                 = LoginInfo
                                                    { lastsuccesstime = Nothing
                                                    , lastfailtime = Nothing
                                                    , consecutivefails = 0
                                                    }
                }

instance Migrate User11 User12 where
    migrate (User11
               { userid11                     
                , userpassword11                
                , usersupervisor11               
                , usercanhavesubaccounts11        
                , useraccountsuspended11          
                , userhasacceptedtermsofservice11  
                , userinfo11                     
                , usersettings11                
                , userpaymentpolicy11             
                , userpaymentaccount11           
                , userfriends11                  
                , userinviteinfo11
                , userlogininfo11       
                }) = User12 
                { userid12                         = userid11
                , userpassword12                   = userpassword11
                , usersupervisor12                 = usersupervisor11
                , useraccountsuspended12           = useraccountsuspended11
                , userhasacceptedtermsofservice12  = userhasacceptedtermsofservice11
                , userinfo12                       = userinfo11
                , usersettings12                   = usersettings11
                , userpaymentpolicy12              = userpaymentpolicy11
                , userpaymentaccount12             = userpaymentaccount11
                , userfriends12                    = userfriends11
                , userinviteinfo12                 = userinviteinfo11
                , userlogininfo12                  = userlogininfo11
                }

-- | This is kinda special. We reset payment changes (since the only changes there
-- are is the system are used to indicate whether a user has free trial or not) since
-- we want to treat free trial specially after it ends, so we need to distinguish
-- between "normal" payment change and free trial.
instance Migrate User12 User where
    migrate (User12
               { userid12                     
                , userpassword12                
                , usersupervisor12               
                , useraccountsuspended12          
                , userhasacceptedtermsofservice12  
                , userinfo12                     
                , usersettings12                
                , userpaymentpolicy12 = Payments.UserPaymentPolicy {temppaymentchange}
                , userpaymentaccount12           
                , userfriends12                  
                , userinviteinfo12
                , userlogininfo12       
                }) = User 
                { userid                         = userid12
                , userpassword                   = userpassword12
                , usersupervisor                 = usersupervisor12
                , useraccountsuspended           = useraccountsuspended12
                , userhasacceptedtermsofservice  = userhasacceptedtermsofservice12
                , userfreetrialexpirationdate    = Just freetrialexpirationdate
                , usersignupmethod               = AccountRequest
                , userinfo                       = userinfo12
                , usersettings                   = usersettings12
                , userpaymentpolicy              = Payments.initialPaymentPolicy
                , userpaymentaccount             = Payments.emptyPaymentAccount {
                    paymentaccountfreesignatures = 100 -- for now we give them
                    -- a lot of free signatures because we don't handle the case
                    -- when they run out of them
                }
                , userfriends                    = userfriends12
                , userinviteinfo                 = userinviteinfo12
                , userlogininfo                  = userlogininfo12
                , userservice                    = Nothing
                , userterminated                 = False
                }
                where
                    freetrialexpirationdate =
                        fromMaybe firstjuly (max firstjuly . fst <$> temppaymentchange)
                    firstjuly = fromJust $ parseMinutesTimeMDY "01-06-2011"

composeFullName :: (BS.ByteString, BS.ByteString) -> BS.ByteString
composeFullName (fstname, sndname) =
    if BS.null sndname
       then fstname
       else fstname `BS.append` BS.fromString " " `BS.append` sndname

userfullname :: User -> BS.ByteString
userfullname u = composeFullName (userfstname $ userinfo u, usersndname $ userinfo u)

instance Migrate UserInfo0 UserInfo where
    migrate (UserInfo0 {
            userfstname0  
          , usersndname0       
          , userpersonalnumber0    
          , usercompanyname0    
          , usercompanynumber0  
          , useraddress0  
          , userzip0     
          , usercity0          
          , usercountry0   
          , userphone0          
          , usermobile0          
          , useremail0        
          }) = UserInfo {
            userfstname = userfstname0 
          , usersndname = usersndname0
          , userpersonalnumber = userpersonalnumber0
          , usercompanyname = usercompanyname0
          , usercompanyposition = BS.empty
          , usercompanynumber = usercompanynumber0
          , useraddress = useraddress0
          , userzip = userzip0
          , usercity = usercity0
          , usercountry = usercountry0
          , userphone = userphone0
          , usermobile = usermobile0
          , useremail = useremail0
          }

instance Migrate UserSettings0 UserSettings where
    migrate (UserSettings0 {
            accounttype0
          , accountplan0
          , signeddocstorage0
          , userpaymentmethod0
          }) = UserSettings {
            accounttype = accounttype0
          , accountplan = accountplan0
          , signeddocstorage = signeddocstorage0
          , userpaymentmethod = userpaymentmethod0
          , preferreddesignmode = Nothing
          }

isAbleToHaveSubaccounts :: User -> Bool
isAbleToHaveSubaccounts user = isNothing $ usersupervisor user

type Users = IxSet User

instance Indexable User where
        empty = ixSet [ ixFun (\x -> [userid x] :: [UserID])
                      , ixFun (\x -> [useremail $ userinfo x] :: [Email])
                      , ixFun (\x -> maybe [] return (usersupervisor x) :: [SupervisorID])
                      , ixFun userfriends
                      , ixFun (\x -> [userservice x] :: [Maybe ServiceID])
                      ]


instance Version User8 where
    mode = extension 8 (Proxy :: Proxy ()) 

instance Version User9 where
    mode = extension 9 (Proxy :: Proxy User8)

instance Version User10 where
    mode = extension 10 (Proxy :: Proxy User9)

instance Version User11 where
    mode = extension 11 (Proxy :: Proxy User10)

instance Version User12 where
    mode = extension 12 (Proxy :: Proxy User11)

instance Version User where
    mode = extension 13 (Proxy :: Proxy User12)

instance Version SignupMethod

instance Version TrustWeaverStorage

instance Version UserAccountType0

instance Version UserAccountType where
    mode = extension 2 (Proxy :: Proxy UserAccountType0)

instance Version PaymentMethod

instance Version UserAccountPlan 

instance Version UserInfo0

instance Version UserInfo where
    mode = extension 1 (Proxy :: Proxy UserInfo0)

instance Version UserSettings0

instance Version UserSettings where
    mode = extension 1 (Proxy :: Proxy UserSettings0)

instance Version DesignMode

instance Version Email

instance Version UserID

instance Version Friend

instance Version Inviter

instance Version InviteInfo

instance Version InviteType

instance Version LoginInfo

instance Version DefaultMainSignatory

instance Version SupervisorID

instance Version ExternalUserID

instance Version UserStats

instance Show ExternalUserID where
    showsPrec prec (ExternalUserID val) = showsPrec prec val

instance Read ExternalUserID where
    readsPrec prec = let make (i,v) = (ExternalUserID i,v) 
                     in map make . readsPrec prec 

instance Show UserID where
    showsPrec prec (UserID val) = showsPrec prec val

instance Read UserID where
    readsPrec prec = let make (i,v) = (UserID i,v) 
                     in map make . readsPrec prec 

instance FromReqURI UserID where
    fromReqURI = readM

instance Show SupervisorID where
    showsPrec prec (SupervisorID val) = showsPrec prec val

instance Read SupervisorID where
    readsPrec prec = let make (i,v) = (SupervisorID i,v) 
                     in map make . readsPrec prec 

instance FromReqURI SupervisorID where
    fromReqURI = readM

modifyUser :: UserID 
           -> (User -> Either String User) 
           -> Update Users (Either String User)
modifyUser uid action = do
  users <- ask
  case getOne (users @= uid) of
    Nothing -> return $ Left "no such user"
    Just user -> 
        case action user of
          Left message -> return $ Left message
          Right newuser -> 
              if userid newuser /= uid
                 then return $ Left "new user must have same id as old one"
              else do
                modify (updateIx uid newuser)
                return $ Right newuser

getUserByEmail :: Maybe Service  -> Email ->  Query Users (Maybe User)
getUserByEmail service email = do
  users <- ask
  return $  getOne (users @= email @= fmap serviceid service)
    
getUserByUserID :: UserID -> Query Users (Maybe User)
getUserByUserID userid = do
  users <- ask
  return $ getOne (users @= userid)

getUsersByFriendUserID :: UserID -> Query Users [User]
getUsersByFriendUserID uid =
  return . toList . (@= (Friend $ unUserID uid)) =<< ask

getUserFriends :: UserID -> Query Users [User]
getUserFriends uid = do
  muser <- getUserByUserID uid
  case muser of
    Nothing -> return []
    Just user -> do
      mfriends <- sequence . map (getUserByUserID . UserID . unFriend) $ userfriends user
      return . map fromJust . filter isJust $ mfriends

getUserSubaccounts :: UserID -> Query Users (Set.Set User)
getUserSubaccounts userid = do
  users <- ask
  return $ toSet (users @= SupervisorID (unUserID userid))

{- |
    Gets all the users that are related to the indicated user.
    They are related if they have the same supervisor,
    or are a supervisor, or are a subaccount (so if a parent, child or sibling).
-}
getUserRelatedAccounts :: UserID -> Query Users [User]
getUserRelatedAccounts userid = do
  muser <- getUserByUserID userid
  case muser of
    Nothing -> return []
    Just (user@User{usersupervisor}) -> do
      users <- ask
      let subaccounts = users @= SupervisorID (unUserID userid)
          superaccounts = maybe IxSet.empty (\SupervisorID{unSupervisorID} -> users @= UserID unSupervisorID) usersupervisor
          siblingaccounts = maybe IxSet.empty (\supervisor -> users @= supervisor) usersupervisor
      return . toList $ subaccounts ||| superaccounts ||| siblingaccounts


addUser :: (BS.ByteString, BS.ByteString)
        -> BS.ByteString 
        -> Password
        -> Maybe UserID
        -> Maybe ServiceID
        -> Update Users (Maybe User)
addUser (fstname, sndname) email passwd maybesupervisor mservice = do
  users <- get
  if (IxSet.size (users @= Email email) /= 0)
   then return Nothing  -- "user with same email address exists"
   else do         
        userid <- getUnique users UserID
        let user = User {  
                   userid                  =  userid
                 , userpassword            =  passwd
                 , usersupervisor          =  fmap (SupervisorID . unUserID) maybesupervisor 
                 , useraccountsuspended    =  False  
                 , userhasacceptedtermsofservice = Nothing
                 , userfreetrialexpirationdate = Nothing
                 , usersignupmethod = AccountRequest
                 , userinfo = UserInfo {
                                    userfstname = fstname
                                  , usersndname = sndname
                                  , userpersonalnumber = BS.empty
                                  , usercompanyname =  BS.empty
                                  , usercompanyposition =  BS.empty
                                  , usercompanynumber  =  BS.empty
                                  , useraddress =  BS.empty
                                  , userzip = BS.empty
                                  , usercity  = BS.empty
                                  , usercountry = BS.empty
                                  , userphone = BS.empty
                                  , usermobile = BS.empty
                                  , useremail =  Email email 
                                   }
                , usersettings  = UserSettings {
                                    accounttype = PrivateAccount
                                  , accountplan = Basic
                                  , signeddocstorage = Nothing
                                  , userpaymentmethod = Undefined
                                  , preferreddesignmode = Nothing
                                  }                   
                , userpaymentpolicy = Payments.initialPaymentPolicy
                , userpaymentaccount = Payments.emptyPaymentAccount
              , userfriends = []
              , userinviteinfo = Nothing
              , userlogininfo = LoginInfo
                                { lastsuccesstime = Nothing
                                , lastfailtime = Nothing
                                , consecutivefails = 0
                                }
              , userservice = mservice
              , userterminated = False
                 }
        modify (updateIx (Email email) user)
        return $ Just user

failure :: String -> Either String a
failure = Left

setUserSupervisor :: UserID -> UserID -> Update Users (Either String User)
setUserSupervisor userid supervisorid = do
    msupervisor <- (getOne . (@= supervisorid)) <$> ask
    let supervisor = fromJust msupervisor
    modifyUser userid $ \user -> do -- Either String monad 
      let luseremail = BS.toString $ unEmail $ useremail $ userinfo user
          suseremail = BS.toString $ unEmail $ useremail $ userinfo supervisor
      when (userid == supervisorid) $ 
         failure "cannot be supervisor of yourself"
      when (isJust $ usersupervisor user) $
         failure "user already has a supervisor"
      when (isNothing $ msupervisor) $
         failure "supervisor id does not exist"
      when (dropWhile (/= '@') luseremail /= dropWhile (/= '@') suseremail) $
         failure $ "users domain names differ " ++ luseremail ++ " vs " ++ suseremail
      return $ user { usersupervisor = Just $ SupervisorID $ unUserID supervisorid}
  
getUserStats :: Query Users UserStats
getUserStats = do
  users <- ask
  return UserStats 
         { usercount = (size users)
         , viralinvitecount = length $ filterByInvite (isInviteType Viral) (toList users)
         , admininvitecount = length $ filterByInvite (isInviteType Admin) (toList users)
         }

getUserStatsByUser :: User -> Query Users UserStats
getUserStatsByUser user = do
  users <- ask
  let invitedusers = filterByInvite isInvitedByUser (toList users)
      isInvitedByUser :: InviteInfo -> Bool
      isInvitedByUser InviteInfo{userinviter} | (unInviter userinviter) == (unUserID . userid $ user) = True
      isInvitedByUser _ = False
  return UserStats 
         { usercount = 1 --sort of silly, but true
         , viralinvitecount = length $ filterByInvite (isInviteType Viral) invitedusers
         , admininvitecount = length $ filterByInvite (isInviteType Admin) invitedusers
         }

filterByInvite :: (InviteInfo -> Bool) -> [User] -> [User]
filterByInvite f users = filter ((maybe False f) . userinviteinfo) users

isInviteType :: InviteType -> InviteInfo -> Bool
isInviteType desiredtype InviteInfo{invitetype} | (isJust invitetype) && ((fromJust invitetype) == desiredtype) = True
isInviteType _ _ = False

getAllUsers :: Query Users [User]
getAllUsers = do
  users <- ask
  let usersSorted = sortBy compareuserfullname (toList users)
      compareuserfullname a b = compare (userfullname a) (userfullname b)
  return usersSorted

setUserPassword :: UserID -> Password -> Update Users (Either String User)
setUserPassword userid newpassword = do
    modifyUser userid $ \user ->
        Right $ user { userpassword = newpassword }

setInviteInfo :: Maybe User -> MinutesTime -> InviteType -> UserID -> Update Users ()
setInviteInfo minviter invitetime' invitetype' uid = do
    let mkInviteInfo user = InviteInfo
                            { userinviter = Inviter . unUserID . userid $ user
                            , invitetime = Just invitetime'
                            , invitetype = Just invitetype'
                            }
    _ <- modifyUser uid $ \user -> Right $ user {userinviteinfo = fmap mkInviteInfo minviter}
    return ()
        

setUserInfo :: UserID -> UserInfo -> Update Users (Either String User)
setUserInfo userid userinfo =
    modifyUser userid $ \user -> 
            Right $ user { userinfo = userinfo }                            

setUserSettings :: UserID -> UserSettings -> Update Users (Either String User)
setUserSettings userid usersettings =
    modifyUser userid $ \user -> 
            Right $ user { usersettings = usersettings }

setPreferredDesignMode :: UserID -> Maybe DesignMode -> Update Users (Either String User)
setPreferredDesignMode userid designmode =
    modifyUser userid $ \user ->
            Right $ user { usersettings = (usersettings user){ preferreddesignmode = designmode } }


setUserPaymentAccount :: UserID -> Payments.UserPaymentAccount -> Update Users (Either String User)
setUserPaymentAccount userid userpaymentaccount =
    modifyUser userid $ \user -> 
            Right $ user {userpaymentaccount = userpaymentaccount}   


setUserPaymentPolicyChange :: UserID -> Payments.UserPaymentPolicy -> Update Users (Either String User)
setUserPaymentPolicyChange userid userpaymentpolicy =
    modifyUser userid $ \user -> 
            Right $ user {userpaymentpolicy = userpaymentpolicy}   
            
freeUserFromPayments :: UserID -> MinutesTime -> Update Users ()
freeUserFromPayments uid freetill =  do
                                    _ <- modifyUser uid $ \user -> 
                                      Right $ user {userpaymentpolicy = Payments.freeTill freetill (userpaymentpolicy user) }   
                                    return ()

{- |
    Records the details of a failed login.
-}
recordFailedLogin :: UserID -> MinutesTime -> Update Users (Either String User)
recordFailedLogin userid time = do
  modifyUser userid $ \user ->
                        Right $ user { userlogininfo = modifyLoginInfo $ userlogininfo user }
  where modifyLoginInfo logininfo =
            logininfo
            { lastfailtime = Just time
            , consecutivefails = (consecutivefails logininfo) + 1
            }   

{- |
    Records the details of a successful login.
-}
recordSuccessfulLogin :: UserID -> MinutesTime -> Update Users (Either String User)
recordSuccessfulLogin userid time = do
  modifyUser userid $ \user ->
                        Right $ user { userlogininfo = modifyLoginInfo $ userlogininfo user }
  where modifyLoginInfo logininfo =
            logininfo
            { lastsuccesstime = Just time
            , consecutivefails = 0
            }   

{- |
   Add a new viewer (friend) given the email address
 -}
addViewerByEmail :: UserID -> Email -> Update Users (Either String User)
addViewerByEmail uid vieweremail = do
  mms <- do users <- ask
            return $ getOne (users @= vieweremail)
  case mms of
    Just ms -> modifyUser uid $ \user ->
                                      Right $ user { userfriends = (Friend (unUserID $ userid ms) : (userfriends user)) }
    Nothing -> return $ Left $ "Användaren existerar ej: " ++ (BS.toString $ unEmail vieweremail)

acceptTermsOfService :: UserID -> MinutesTime -> Update Users (Either String User)
acceptTermsOfService userid minutestime = 
    modifyUser userid $ \user -> 
        Right $ user {
              userhasacceptedtermsofservice = Just minutestime
            , userfreetrialexpirationdate  = Just $ (60*24*30) `minutesAfter` minutestime
        }

setFreeTrialExpirationDate :: UserID -> Maybe MinutesTime -> Update Users (Either String User)
setFreeTrialExpirationDate userid date = 
    modifyUser userid $ \user -> 
        Right $ user { userfreetrialexpirationdate = date }

setSignupMethod :: UserID -> SignupMethod -> Update Users (Either String User)
setSignupMethod userid signupmethod = 
    modifyUser userid $ \user -> 
        Right $ user { usersignupmethod = signupmethod }

addFreePaymentsForInviter ::MinutesTime -> User -> Update Users ()
addFreePaymentsForInviter now u = do
                           case (fmap userinviter $ userinviteinfo u) of
                            Nothing -> return ()   
                            Just (Inviter iid) -> do
                              users <- ask
                              let minviter = getOne (users @= (UserID iid))    
                              case minviter of
                                Nothing -> return ()   
                                Just inviter ->  do 
                                                 _<- modifyUser (userid inviter) $ \user -> 
                                                  Right $ user {userpaymentpolicy = Payments.extendFreeTmpChange now 7 (userpaymentpolicy user)}
                                                 return ()
                           
exportUsersDetailsToCSV :: Query Users BS.ByteString
exportUsersDetailsToCSV = do
  users <- ask
  let fields user = [userfullname user, unEmail $ useremail $ userinfo user]
      content = BS.intercalate (BS.fromString ",") <$> fields
  return $ BS.unlines $ content <$> (toList users)

  
getUserPaymentSchema::User -> IO (Payments.PaymentScheme)
getUserPaymentSchema User{userpaymentpolicy } = do
                               now <- getMinutesTime
                               model <- update $ Payments.GetPaymentModel (Payments.paymentaccounttype userpaymentpolicy ) 
                               let paymentChange = case Payments.temppaymentchange userpaymentpolicy  of 
                                                     Nothing -> Payments.custompaymentchange  userpaymentpolicy 
                                                     Just (expires,tchange) -> 
                                                        if (now < expires)    
                                                        then Payments.custompaymentchange userpaymentpolicy 
                                                        else Payments.mergeChanges tchange (Payments.custompaymentchange userpaymentpolicy)
                               return $ (paymentChange,model)                                                                  

takeImmediatelyPayment::User -> Bool
takeImmediatelyPayment user = Payments.requiresImmediatelyPayment $ userpaymentpolicy user

{- 

Template Haskell derivations should be kept at the end of the file

-}


-- create types for event serialization
$(mkMethods ''Users [ 'getUserByUserID
                    , 'getUserByEmail
                    , 'addUser
                    , 'getUserStats
                    , 'getUserStatsByUser
                    , 'getAllUsers
                    , 'setUserPassword
                    , 'setInviteInfo
                    , 'setUserInfo
                    , 'setUserSettings
                    , 'setPreferredDesignMode
                    , 'setUserPaymentAccount
                    , 'setUserPaymentPolicyChange
                    --, 'freeUserFromPayments
                    , 'recordFailedLogin
                    , 'recordSuccessfulLogin
                    , 'getUserSubaccounts
                    , 'getUserRelatedAccounts
                    , 'getUsersByFriendUserID
                    , 'getUserFriends
                    , 'acceptTermsOfService
                    , 'setFreeTrialExpirationDate
                    , 'setSignupMethod
                    , 'exportUsersDetailsToCSV
                    , 'addViewerByEmail
                      -- the below should be only used carefully and by admins
                    --, 'addFreePaymentsForInviter
                    , 'setUserSupervisor
                    ])

$(deriveSerializeFor [ ''User
                     , ''User12
                     , ''User11
                     , ''User10
                     , ''User9
                     , ''User8

                     , ''SignupMethod
                     , ''TrustWeaverStorage
                     , ''UserAccountType
                     , ''UserAccountType0
                     , ''PaymentMethod
                     , ''UserInfo0
                     , ''UserStats
                     , ''Email
                     , ''InviteType
                     , ''LoginInfo
                     , ''InviteInfo
                     , ''Friend
                     , ''UserSettings
                     , ''UserSettings0
                     , ''DesignMode
                     , ''UserInfo
                     , ''SupervisorID
                     , ''UserID
                     , ''Inviter
                     , ''DefaultMainSignatory
                     , ''UserAccountPlan
                     ])

instance Component Users where
  type Dependencies Users = End
  initialValue = IxSet.empty
