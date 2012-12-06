{-# LANGUAGE CPP #-}
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
          ) where
import Control.Monad.State
import Data.Functor
import Happstack.Server hiding (simpleHTTP,dir,path,https)
import Happstack.Fields
import Utils.IO
import Utils.Monad
import Utils.Monoid
import Utils.Prelude
import Kontra
import Administration.AdministrationView
import Doc.Model
import Doc.DocStateData
import Company.Model
import KontraLink
import MinutesTime
import DB
import User.UserControl
import User.UserView
import User.Model
import Data.Maybe
import Data.Char
import Templates.Templates
import Util.FlashUtil
import Data.List
import Util.MonadUtils
import qualified Log
import Doc.DocSeal (sealDocument)
import Util.HasSomeUserInfo
import InputValidation
import User.Utils
import ScriveByMail.Model
import Crypto.RNG(random)
import Util.Actor
import Payments.Action
import Payments.Model
import Payments.Config
import qualified Payments.Stats
import Recurly

import InspectXMLInstances ()
import InspectXML
import Util.CSVUtil
import ListUtil
import Text.JSON
import Mails.Model
import Util.HasSomeCompanyInfo
import CompanyAccounts.CompanyAccountsControl
import CompanyAccounts.Model
import Util.SignatoryLinkUtils
import Stats.Control (getUsersAndStatsInv)
import User.History.Model
import qualified Templates.Fields as F
import Control.Logic
import Doc.DocInfo
import EvidenceLog.Model
import Routing
import qualified Stats.Control as Stats
import qualified Company.CompanyControl as Company
import qualified CompanyAccounts.CompanyAccountsControl as CompanyAccounts
import Happstack.StaticRouting(Route, choice, dir)
import Text.JSON.Gen

adminonlyRoutes :: Route (KontraPlus Response)
adminonlyRoutes =
  fmap onlySalesOrAdmin $ choice $ [
          hGet $ toK0 $ showAdminMainPage
        , dir "createuser" $ hPost $ toK0 $ handleCreateUser
        , dir "useradminforsales" $ hGet $ toK0 $ showAdminUsersForSales
        , dir "userslist" $ hGet $ toK0 $ jsonUsersList
        , dir "useradmin" $ hGet $ toK1 $ showAdminUsers . Just
        , dir "useradmin" $ hGet $ toK0 $ showAdminUsers Nothing
        , dir "useradmin" $ dir "usagestats" $ hGet $ toK1 $ Stats.showAdminUserUsageStats
        , dir "useradmin" $ hPost $ toK1 $ handleUserChange
        , dir "useradmin" $ dir "sendinviteagain" $ hPost $ toK0 $ sendInviteAgain
        , dir "useradmin" $ dir "payments" $ hGet $ toK1 $ showAdminUserPayments
        , dir "useradmin" $ dir "payments" $ hPost $ toK1 $ handleUserPaymentsChange
        , dir "companyadmin" $ hGet $ toK0 $ showAdminCompanies
        , dir "companyadmin" $ hGet $ toK1 $ showAdminCompany
        , dir "companyadmin" $ dir "branding" $ Company.adminRoutes
        , dir "companyadmin" $ dir "users" $ hGet $ toK1 $ showAdminCompanyUsers
        , dir "companyadmin" $ dir "users" $ hPost $ toK1 $ handlePostAdminCompanyUsers
        , dir "companyadmin" $ dir "payments" $ hGet $ toK1 $ showAdminCompanyPayments
        , dir "companyadmin" $ dir "payments" $ hPost $ toK1 $ handleCompanyPaymentsChange
        , dir "companyaccounts" $ hGet  $ toK1 $ CompanyAccounts.handleCompanyAccountsForAdminOnly
        , dir "companyadmin" $ dir "usagestats" $ hGet $ toK1 $ Stats.showAdminCompanyUsageStats
        , dir "companyadmin" $ hPost $ toK1 $ handleCompanyChange
        , dir "functionalitystats" $ hGet $ toK0 $ showFunctionalityStats

        , dir "documents" $ hGet $ toK0 $ showDocuments
        , dir "documentslist" $ hGet $ toK0 $ jsonDocuments

        , dir "allstatscsv" $ hGet $ toK0 $ Stats.handleDocStatsCSV
        , dir "userstatscsv" $ hGet $ toK0 $ Stats.handleUserStatsCSV
        , dir "signstatscsv" $ hGet $ toK0 $ Stats.handleSignStatsCSV
        , dir "dochistorycsv" $ hGet $ toK0 $ Stats.handleDocHistoryCSV
        , dir "signhistorycsv" $ hGet $ toK0 $ Stats.handleSignHistoryCSV
        , dir "userslistcsv" $ hGet $ toK0 $ handleUsersListCSV
        , dir "paymentsstats.csv" $ hGet $ toK0 $ Payments.Stats.handlePaymentsStatsCSV

        , dir "statistics"   $ hGet $ toK0 $ Stats.handleAdminSystemUsageStats
        , dir "statsbyday"   $ hGet $ toK0 $ Stats.handleAdminSystemUsageStatsByDayJSON
        , dir "statsbymonth" $ hGet $ toK0 $ Stats.handleAdminSystemUsageStatsByMonthJSON

        , dir "companies" $ hGet $ toK0 $ jsonCompanies
  ]

daveRoutes :: Route (KontraPlus Response)
daveRoutes =
  fmap onlyAdmin $ choice $ [
       dir "document"      $ hGet $ toK1 $ daveDocument
     , dir "document"      $ hGet $ toK2 $ daveSignatoryLink
     , dir "user"          $ hGet $ toK1 $ daveUser
     , dir "userhistory"   $ hGet $ toK1 $ daveUserHistory
     , dir "company"       $ hGet $ toK1 $ daveCompany
     , dir "reseal" $ hPost $ toK1 $ resealFile
     , dir "backdoor" $ hGet $ toK1 $ handleBackdoorQuery
    ]
{- | Main page. Redirects users to other admin panels -}
showAdminMainPage :: Kontrakcja m => m String
showAdminMainPage = onlySalesOrAdmin $ do
    ctx <- getContext
    adminMainPage ctx

{- | Process view for finding a user in basic administration. If provided with userId string as param
it allows to edit user details -}
showAdminUsers :: Kontrakcja m => Maybe UserID -> m String
showAdminUsers Nothing = onlySalesOrAdmin adminUsersPage

showAdminUsers (Just userId) = onlySalesOrAdmin $ do
  muser <- dbQuery $ GetUserByID userId
  case muser of
    Nothing -> internalError
    Just user -> adminUserPage user =<< getCompanyForUser user

showAdminCompanies :: Kontrakcja m => m String
showAdminCompanies = onlySalesOrAdmin $  adminCompaniesPage

showAdminCompany :: Kontrakcja m => CompanyID -> m String
showAdminCompany companyid = onlySalesOrAdmin $ do
  company  <- guardJustM . dbQuery $ GetCompany companyid
  mmailapi <- dbQuery $ GetCompanyMailAPI companyid
  adminCompanyPage company mmailapi

showAdminCompanyPayments :: Kontrakcja m => CompanyID -> m String
showAdminCompanyPayments companyid = onlySalesOrAdmin $ do
  RecurlyConfig {..} <- ctxrecurlyconfig <$> getContext
  mpaymentplan <- dbQuery $ GetPaymentPlan (Right companyid)
  quantity <- dbQuery $ GetCompanyQuantity companyid
  adminCompanyPaymentPage mpaymentplan quantity companyid recurlySubdomain

showAdminUserPayments :: Kontrakcja m => UserID -> m String
showAdminUserPayments userid = onlySalesOrAdmin $ do
  RecurlyConfig {..} <- ctxrecurlyconfig <$> getContext
  mpaymentplan <- dbQuery $ GetPaymentPlan (Left userid)
  user <- guardJustM $ dbQuery $ GetUserByID userid
  adminUserPaymentPage userid mpaymentplan (usercompany user) recurlySubdomain

jsonCompanies :: Kontrakcja m => m JSValue
jsonCompanies = onlySalesOrAdmin $ do
    params <- getListParamsNew
    let
      filters = companySearchingFromParams params
      sorting = companySortingFromParams params
      (offset, limit) = companyPaginationFromParams companiesPageSize params
      companiesPageSize = 100

    allCompanies <- dbQuery $ GetCompanies filters sorting offset limit
    let companies = PagedList { list       = allCompanies
                              , params     = params
                              , pageSize   = companiesPageSize
                              }
    runJSONGenT $ do
            valueM "list" $ forM (take companiesPageSize $ allCompanies) $ \company -> runJSONGenT $ do
                object "fields" $ do
                    value "id"            $ show . companyid $ company
                    value "companyname"   $ getCompanyName $ company
                    value "companynumber" $ getCompanyNumber $ company
                    value "companyaddress" $ companyaddress . companyinfo $ company
                    value "companyzip"     $ companyzip . companyinfo $ company
                    value "companycity"    $ companycity . companyinfo $ company
                    value "companycountry" $ companycountry . companyinfo $ company
                value "link" $ show $ LinkCompanyAdmin $ Just $ companyid $ company
            value "paging" $ pagingParamsJSON companies

companySearchingFromParams :: ListParams -> [CompanyFilter]
companySearchingFromParams params =
  case listParamsSearching params of
    "" -> []
    x -> [CompanyFilterByString x]

companySortingFromParams :: ListParams -> [AscDesc CompanyOrderBy]
companySortingFromParams params =
   concatMap x (listParamsSorting params)
  where
    x "companyname"       = [Asc CompanyOrderByName]
    x "companynameREV"    = [Desc CompanyOrderByName]
    x "companynumber"     = [Asc CompanyOrderByNumber]
    x "companynumberREV"  = [Desc CompanyOrderByNumber]
    x "companyaddress"    = [Asc CompanyOrderByAddress]
    x "companyaddressREV" = [Desc CompanyOrderByAddress]
    x "companyzip"        = [Asc CompanyOrderByZip]
    x "companyzipREV"     = [Desc CompanyOrderByZip]
    x "companycity"       = [Asc CompanyOrderByCity]
    x "companycityREV"    = [Desc CompanyOrderByCity]
    x "companycountry"    = [Asc CompanyOrderByCountry]
    x "companycountryREV" = [Desc CompanyOrderByCountry]
    x _                   = []

companyPaginationFromParams :: Int -> ListParams -> (Integer,Integer)
companyPaginationFromParams pageSize params = (fromIntegral (listParamsOffset params), fromIntegral pageSize)


showAdminCompanyUsers :: Kontrakcja m => CompanyID -> m String
showAdminCompanyUsers cid = onlySalesOrAdmin $ adminCompanyUsersPage cid


showAdminUsersForSales :: Kontrakcja m => m String
showAdminUsersForSales = onlySalesOrAdmin $ adminUsersPageForSales

handleUsersListCSV :: Kontrakcja m => m CSV
handleUsersListCSV = onlySalesOrAdmin $ do
  users <- getUsersAndStatsInv [] [] (0,maxBound)
  return $ CSV { csvHeader = ["id", "fstname", "sndname", "email", "company", "position","tos"]
               , csvFilename = "userslist.csv"
               , csvContent = map csvline $ filter active users
               }
  where
        active (u,_,_,_) =   (not (useraccountsuspended u)) && (isJust $ userhasacceptedtermsofservice u)
        csvline (u,mc,_,_) =
                          [ show $ userid u
                          , getFirstName u
                          , getLastName u
                          , getEmail u
                          , getCompanyName mc
                          , usercompanyposition $ userinfo u
                          , show $ fromJust $ userhasacceptedtermsofservice u
                          ]


userSearchingFromParams :: ListParams -> [UserFilter]
userSearchingFromParams params =
  case listParamsSearching params of
    "" -> []
    x -> [UserFilterByString x]

userSortingFromParams :: ListParams -> [AscDesc UserOrderBy]
userSortingFromParams params =
   (concatMap x (listParamsSorting params)) ++ [Asc UserOrderByName]
  where
    x "username"    = [Asc UserOrderByName]
    x "usernameREV" = [Desc UserOrderByName]
    x "email"       = [Asc UserOrderByEmail]
    x "emailREV"    = [Desc UserOrderByEmail]
    x "company"     = [Asc UserOrderByCompanyName]
    x "companyREV"  = [Desc UserOrderByCompanyName]
    x "tos"         = [Asc UserOrderByAccountCreationDate]
    x "tosREV"      = [Desc UserOrderByAccountCreationDate]
    x _             = [Asc UserOrderByName]


jsonUsersList ::Kontrakcja m => m JSValue
jsonUsersList = onlySalesOrAdmin $ do
    params <- getListParamsNew
    let filters = userSearchingFromParams params
        sorting = userSortingFromParams params
        pagination = ((listParamsOffset params),(usersPageSize * 4))
        usersPageSize = 100
    allUsers <- getUsersAndStatsInv filters sorting pagination
    let users = PagedList { list       = allUsers
                          , params     = params
                          , pageSize   = usersPageSize
                          }

    runJSONGenT $ do
            valueM "list" $ forM (take usersPageSize $ list users) $ \(user,mcompany,docstats,itype) -> runJSONGenT $ do
                object "fields" $ do
                    value "id" $ show $ userid user
                    value "username" $ getFullName user
                    value "email"    $ getEmail user
                    value "company"  $ getCompanyName mcompany
                    value "phone"    $ userphone $ userinfo user
                    value "tos"      $ maybe "-" show (userhasacceptedtermsofservice user)
                    value "signed_1m" $ show $ signaturecount1m docstats
                    value "signed_2m" $ show $ signaturecount2m docstats
                    value "signed_3m" $ show $ signaturecount3m docstats
                    value "signed_6m" $ show $ signaturecount6m docstats
                    value "signed_12m" $ show $ signaturecount12m docstats
                    value "signed_docs" $ show $ signaturecount docstats
                    value "uploaded_docs" $ show $ doccount docstats
                    value "viral_invites" $ itype == Viral
                    value "admin_invites" $ itype == Admin
                value "link" $ show $ LinkUserAdmin $ Just $ userid user
            value "paging" $ pagingParamsJSON users

{- | Handling user details change. It reads user info change -}
handleUserChange :: Kontrakcja m => UserID -> m KontraLink
handleUserChange uid = onlySalesOrAdmin $ do
  ctx <- getContext
  _ <- getAsString "change"
  museraccounttype <- getField "useraccounttype"
  olduser <- guardJustM $ dbQuery $ GetUserByID uid
  user <- case (museraccounttype, usercompany olduser, useriscompanyadmin olduser) of
    (Just "companyadminaccount", Just _companyid, False) -> do
      --then we just want to make this account an admin
      newuser <- guardJustM $ do
        _ <- dbUpdate $ SetUserCompanyAdmin uid True
        _ <- dbUpdate $ LogHistoryDetailsChanged uid (ctxipnumber ctx) (ctxtime ctx)
             [("is_company_admin", "false", "true")]
             (userid <$> ctxmaybeuser ctx)
        dbQuery $ GetUserByID uid
      return newuser
    (Just "companyadminaccount", Nothing, False) -> do
      --then we need to create a company and make this account an admin
      --we also need to tie all the existing docs to the company
      newuser <- guardJustM $ do
        company <- dbUpdate $ CreateCompany Nothing
        _ <- dbUpdate $ SetUserCompany uid (Just $ companyid company)
        _ <- dbUpdate
                  $ LogHistoryDetailsChanged uid (ctxipnumber ctx) (ctxtime ctx)
                                             [("company_id", "null", show $ companyid company)]
                                             (userid <$> ctxmaybeuser ctx)
        _ <- dbUpdate $ SetUserCompanyAdmin uid True
        _ <- switchPlanToCompany uid (companyid company) -- migrate payment plan to company
        _ <- dbUpdate
                  $ LogHistoryDetailsChanged uid (ctxipnumber ctx) (ctxtime ctx)
                                             [("is_company_admin", "false", "true")]
                                             (userid <$> ctxmaybeuser ctx)
        dbQuery $ GetUserByID uid
      return newuser
    (Just "companystandardaccount", Just _companyid, True) -> do
      --then we just want to downgrade this account to a standard
      newuser <- guardJustM $ do
        _ <- dbUpdate $ SetUserCompanyAdmin uid False
        _ <- dbUpdate
                 $ LogHistoryDetailsChanged uid (ctxipnumber ctx) (ctxtime ctx)
                                            [("is_company_admin", "true", "false")]
                                            (userid <$> ctxmaybeuser ctx)
        dbQuery $ GetUserByID uid
      return newuser
    (Just "companystandardaccount", Nothing, False) -> do
      --then we need to create a company and make this account a standard user
      --we also need to tie all the existing docs to the company
      newuser <- guardJustM $ do
        company <- dbUpdate $ CreateCompany Nothing
        _ <- dbUpdate $ SetUserCompany uid (Just $ companyid company)
        -- cancel payment plan since they are now not admin
        mplan <- dbQuery $ GetPaymentPlan (Left uid)
        case mplan of
          Just pp -> do
            _ <- liftIO $ deleteAccount curl_exe (recurlyAPIKey $ ctxrecurlyconfig ctx) (show $ ppAccountCode pp)
            _ <- dbUpdate $ DeletePaymentPlan (Left uid)
            return ()
          Nothing -> return ()
        _ <- dbUpdate
                 $ LogHistoryDetailsChanged uid (ctxipnumber ctx) (ctxtime ctx)
                                            [("company_id", "null", show $ companyid company)]
                                            (userid <$> ctxmaybeuser ctx)
        dbQuery $ GetUserByID uid
      return newuser
    (Just "privateaccount", Just companyid, _) -> do
      --then we need to downgrade this user and possibly delete their company
      --we also need to untie all their existing docs from the company
      --we may also need to delete the company if it's empty, but i haven't implemented this bit
      newuser <- guardJustM $ do
        _ <- dbUpdate $ SetUserCompany uid Nothing
        -- moving from company to private account, we should cancel payment plan
        -- if there are no more users in the company
        mplan <- dbQuery $ GetPaymentPlan (Right companyid)
        case mplan of
          Just pp -> do
            cas <- dbQuery $ GetCompanyAccounts companyid
            when_ (null cas) $ do -- no users left, we delete the plan!
                when_ (ppPaymentPlanProvider pp == RecurlyProvider) $
                  liftIO $ deleteAccount curl_exe (recurlyAPIKey $ ctxrecurlyconfig ctx) (show $ ppAccountCode pp)
                dbUpdate $ DeletePaymentPlan (Right companyid)
          Nothing -> return ()

        _ <- dbUpdate
                 $ LogHistoryDetailsChanged uid (ctxipnumber ctx) (ctxtime ctx)
                                            [("company_id", show companyid, "null")]
                                            (userid <$> ctxmaybeuser ctx)
        dbQuery $ GetUserByID uid
      return newuser
    _ -> return olduser
  infoChange <- getUserInfoChange
  _ <- dbUpdate $ SetUserInfo uid $ infoChange $ userinfo user
  _ <- dbUpdate
           $ LogHistoryUserInfoChanged uid (ctxipnumber ctx) (ctxtime ctx)
                                       (userinfo user) (infoChange $ userinfo user)
                                       (userid <$> ctxmaybeuser ctx)
  settingsChange <- getUserSettingsChange
  _ <- dbUpdate $ SetUserSettings uid $ settingsChange $ usersettings user
  isfree <- isFieldSet "freeuser"
  _ <- dbUpdate $ SetUserIsFree uid isfree
  return $ LinkUserAdmin $ Just uid

{- | Handling company details change. It reads user info change -}
handleCompanyChange :: Kontrakcja m => CompanyID -> m KontraLink
handleCompanyChange companyid = onlySalesOrAdmin $ do
  _ <- getAsString "change"
  company <- guardJustM $ dbQuery $ GetCompany companyid
  companyInfoChange <- getCompanyInfoChange
  _ <- dbUpdate $ SetCompanyInfo companyid (companyInfoChange $ companyinfo company)
  mmailapi <- dbQuery $ GetCompanyMailAPI companyid
  when_ (isNothing mmailapi) $ do
    key <- random
    dbUpdate $ SetCompanyMailAPIKey companyid key 1000
  return $ LinkCompanyAdmin $ Just companyid

handleCompanyPaymentsChange :: Kontrakcja m => CompanyID -> m KontraLink
handleCompanyPaymentsChange companyid = onlySalesOrAdmin $ do
  mplan <- readField "priceplan"
  mstatus <- readField "status"
  let status = fromMaybe ActiveStatus mstatus
  migratep <- isFieldSet "migrate"
  deletep <- isFieldSet "delete"
  case (migratep, deletep, mplan) of
    (True, _, _) -> migrateCompanyPlan companyid
    (False, True, _) -> deleteCompanyPlan companyid
    (_, _, Just plan) -> addCompanyPlanManual companyid plan status
    _ -> return ()
  return $ LinkCompanyAdminPayments companyid
  
migrateCompanyPlan :: Kontrakcja m => CompanyID -> m ()
migrateCompanyPlan companyid = do
  migratetype <- getField' "migratetype"
  case migratetype of
    "userid" -> do
      muserid <- readField "id"
      case muserid of
        Just dest -> do
          _ <- changePaymentPlanOwner (Right companyid) (Left dest)
          return ()
        _ -> return ()
        
    "companyid" -> do
      mcompanyid <- readField "id"
      case mcompanyid of
        Just dest -> do
          _ <- changePaymentPlanOwner (Right companyid) (Right dest)
          return ()
        _ -> return ()
    _ -> return ()
    
deleteCompanyPlan :: Kontrakcja m => CompanyID -> m ()
deleteCompanyPlan companyid = do
  dbUpdate $ DeletePaymentPlan (Right companyid)

addCompanyPlanManual :: Kontrakcja m => CompanyID -> PricePlan -> PaymentPlanStatus -> m ()
addCompanyPlanManual companyid pp status = do
  case pp of
    FreePricePlan -> do
      mpaymentplan <- dbQuery $ GetPaymentPlan (Right companyid)
      case mpaymentplan of
        Nothing -> return ()
        Just PaymentPlan {ppPaymentPlanProvider = NoProvider} -> do
          _ <- dbUpdate $ DeletePaymentPlan (Right companyid)
          return ()
        Just _ -> return ()
    plan -> do
      mpaymentplan <- dbQuery $ GetPaymentPlan (Right companyid)
      quantity <- dbQuery $ GetCompanyQuantity companyid
      time <- ctxtime <$> getContext
      case mpaymentplan of
        Nothing -> do
          ac <- dbUpdate $ GetAccountCode
          let paymentplan = PaymentPlan { ppAccountCode         = ac
                                        , ppID                  = Right companyid
                                        , ppPricePlan           = plan
                                        , ppPendingPricePlan    = plan
                                        , ppStatus              = status
                                        , ppPendingStatus       = status
                                        , ppQuantity            = quantity
                                        , ppPendingQuantity     = quantity
                                        , ppPaymentPlanProvider = NoProvider
                                        , ppDunningStep         = Nothing
                                        , ppDunningDate         = Nothing
                                        , ppBillingEndDate      = time
                                        }
          _ <- dbUpdate $ SavePaymentPlan paymentplan time
          _ <- Payments.Stats.record time Payments.Stats.SignupAction NoProvider quantity plan (Right companyid) ac
          return ()
        Just paymentplan | ppPaymentPlanProvider paymentplan == NoProvider -> do
          let paymentplan' = paymentplan { ppPricePlan        = plan
                                         , ppPendingPricePlan = plan
                                         , ppStatus           = status
                                         , ppPendingStatus    = status
                                         , ppQuantity         = quantity
                                         , ppPendingQuantity  = quantity
                                         }
          _ <- dbUpdate $ SavePaymentPlan paymentplan' time
          _ <- Payments.Stats.record time Payments.Stats.ChangeAction NoProvider quantity plan (Right companyid) (ppAccountCode paymentplan')
          return ()
        Just _ -> do -- must be a Recurly payment plan; maybe flash message?
          return ()

handleUserPaymentsChange :: Kontrakcja m => UserID -> m KontraLink
handleUserPaymentsChange userid = onlySalesOrAdmin $ do
  mplan <- readField "priceplan"
  mstatus <- readField "status"
  let status = fromMaybe ActiveStatus mstatus
  migratep <- isFieldSet "migrate"
  deletep <- isFieldSet "delete"
  case (migratep, deletep, mplan) of
    (True, _, _) -> migratePlan userid
    (False, True, _) -> deletePlan userid
    (_, _, Just plan) -> addManualPricePlan userid plan status
    _ -> return ()
  return $ LinkUserAdminPayments userid
  
migratePlan :: Kontrakcja m => UserID -> m ()
migratePlan userid = do
  migratetype <- getField' "migratetype"
  case migratetype of
    "userid" -> do
      muserid <- readField "id"
      case muserid of
        Just dest -> do
          _ <- changePaymentPlanOwner (Left userid) (Left dest)
          return ()
        _ -> return ()
        
    "companyid" -> do
      mcompanyid <- readField "id"
      case mcompanyid of
        Just dest -> do
          _ <- changePaymentPlanOwner (Left userid) (Right dest)
          return ()
        _ -> return ()
    _ -> return ()
    
deletePlan :: Kontrakcja m => UserID -> m ()
deletePlan userid = do
  dbUpdate $ DeletePaymentPlan (Left userid)

addManualPricePlan :: Kontrakcja m => UserID -> PricePlan -> PaymentPlanStatus -> m ()
addManualPricePlan  uid priceplan status =
  case priceplan of
    FreePricePlan -> do
      mpaymentplan <- dbQuery $ GetPaymentPlan $ Left uid
      case mpaymentplan of
        Just PaymentPlan{ppPaymentPlanProvider = NoProvider} -> do
          _ <- dbUpdate $ DeletePaymentPlan $ Left uid
          return ()
        _ -> do
          return ()
    plan -> do
      mpaymentplan <- dbQuery $ GetPaymentPlan $ Left uid
      let quantity = 1
      time <- ctxtime <$> getContext
      case mpaymentplan of
        Nothing -> do
          ac <- dbUpdate $ GetAccountCode
          let paymentplan = PaymentPlan { ppAccountCode         = ac
                                        , ppID                  = Left uid
                                        , ppPricePlan           = plan
                                        , ppPendingPricePlan    = plan
                                        , ppStatus              = status
                                        , ppPendingStatus       = status
                                        , ppQuantity            = quantity
                                        , ppPendingQuantity     = quantity
                                        , ppPaymentPlanProvider = NoProvider
                                        , ppDunningStep         = Nothing
                                        , ppDunningDate         = Nothing
                                        , ppBillingEndDate      = time
                                        }
          _ <- dbUpdate $ SavePaymentPlan paymentplan time
          _ <- Payments.Stats.record time Payments.Stats.SignupAction NoProvider quantity plan (Left uid) ac
          return ()
        Just paymentplan | ppPaymentPlanProvider paymentplan == NoProvider -> do
          let paymentplan' = paymentplan { ppPricePlan        = plan
                                         , ppPendingPricePlan = plan
                                         , ppStatus           = status
                                         , ppPendingStatus    = status
                                         , ppQuantity         = quantity
                                         , ppPendingQuantity  = quantity
                                         }
          _ <- dbUpdate $ SavePaymentPlan paymentplan' time
          _ <- Payments.Stats.record time Payments.Stats.ChangeAction NoProvider quantity plan (Left uid) (ppAccountCode paymentplan')
          return ()
        Just _ -> do -- must be a Recurly payment plan; maybe flash message?
          return ()

handleCreateUser :: Kontrakcja m => m KontraLink
handleCreateUser = onlySalesOrAdmin $ do
    email <- map toLower <$> getAsString "email"
    fstname <- getAsString "fstname"
    sndname <- getAsString "sndname"
    custommessage <- getField "custommessage"
    lang <- guardJustM $ readField "lang"
    muser <- createNewUserByAdmin email (fstname, sndname) custommessage Nothing lang
    when (isNothing muser) $
      addFlashM flashMessageUserWithSameEmailExists
    -- FIXME: where to redirect?
    return LoopBack

handlePostAdminCompanyUsers :: Kontrakcja m => CompanyID -> m KontraLink
handlePostAdminCompanyUsers companyid = onlySalesOrAdmin $ do
  privateinvite <- isFieldSet "privateinvite"
  if privateinvite
    then handlePrivateUserCompanyInvite companyid
    else handleCreateCompanyUser companyid
  return $ LinkCompanyUserAdmin companyid


handlePrivateUserCompanyInvite :: Kontrakcja m => CompanyID -> m ()
handlePrivateUserCompanyInvite companyid = onlySalesOrAdmin $ do
  ctx <- getContext
  user <- guardJust $ ctxmaybeuser ctx
  email <- Email <$> getCriticalField asValidEmail "email"
  existinguser <- guardJustM $ dbQuery $ GetUserByEmail email
  _ <- dbUpdate $ AddCompanyInvite CompanyInvite{
          invitedemail = email
        , invitedfstname = getFirstName existinguser
        , invitedsndname = getLastName existinguser
        , invitingcompany = companyid
        }
  company <- guardJustM $ dbQuery $ GetCompany companyid
  sendTakeoverPrivateUserMail user company existinguser

handleCreateCompanyUser :: Kontrakcja m => CompanyID -> m ()
handleCreateCompanyUser companyid = onlySalesOrAdmin $ do
  email <- getCriticalField asValidEmail "email"
  fstname <- getCriticalField asValidName "fstname"
  sndname <- getCriticalField asValidName "sndname"
  custommessage <- joinEmpty <$> getField "custommessage"
  Log.debug $ "Custom message when creating an account " ++ show custommessage
  lang <- guardJustM $ readField "lang"
  admin <- isFieldSet "iscompanyadmin"
  muser <- createNewUserByAdmin email (fstname, sndname) custommessage (Just (companyid, admin)) lang
  when (isNothing muser) $
      addFlashM flashMessageUserWithSameEmailExists
  return ()

{- | Reads params and returns function for conversion of company info.  With no param leaves fields unchanged -}
getCompanyInfoChange :: Kontrakcja m => m (CompanyInfo -> CompanyInfo)
getCompanyInfoChange = do
  mcompanyname    <- getField "companyname"
  mcompanynumber  <- getField "companynumber"
  mcompanyaddress <- getField "companyaddress"
  mcompanyzip     <- getField "companyzip"
  mcompanycity    <- getField "companycity"
  mcompanycountry <- getField "companycountry"
  mcompanyemaildomain <- getField "companyemaildomain"
  return $ \CompanyInfo{..} ->  CompanyInfo {
        companyname        = fromMaybe companyname mcompanyname
      , companynumber      = fromMaybe companynumber mcompanynumber
      , companyaddress     = fromMaybe companyaddress mcompanyaddress
      , companyzip         = fromMaybe companyzip mcompanyzip
      , companycity        = fromMaybe companycity mcompanycity
      , companycountry     = fromMaybe companycountry mcompanycountry
      , companyemaildomain = case mcompanyemaildomain of
                               Just a | not $ null a -> Just a
                               _                     -> Nothing
    }

{- | Reads params and returns function for conversion of user settings.  No param leaves fields unchanged -}
getUserSettingsChange :: Kontrakcja m => m (UserSettings -> UserSettings)
getUserSettingsChange = do
  mlang <- readField "userlang"
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
  musermobile          <- getField "usermobile"
  museremail           <- fmap Email <$> getField "useremail"
  musercompanyname     <- getField "usercompanyname"
  musercompanynumber   <- getField "usercompanynumber"
  return $ \UserInfo{..} -> UserInfo {
        userfstname         = fromMaybe userfstname muserfstname
      , usersndname         = fromMaybe usersndname musersndname
      , userpersonalnumber  = fromMaybe userpersonalnumber muserpersonalnumber
      , usercompanyposition = fromMaybe usercompanyposition musercompanyposition
      , userphone           = fromMaybe userphone muserphone
      , usermobile          = fromMaybe usermobile musermobile
      , useremail           = fromMaybe useremail museremail
      , usercompanyname     = fromMaybe usercompanyname musercompanyname
      , usercompanynumber   = fromMaybe usercompanynumber musercompanynumber
    }

{-
Sales leads stats:

User name
User email
Total finalized docs (total signatures)
Sales rep (editable, free text)
Status (1-5) (editable, free text)
Subaccounts
User company
User title
User phone
Date TOS accepted
Subacc (y/n)/Superaccount
-}

{-
Billing stats:

Superuser Company name
Superuser email
Payment plan
Next billing date
Last billing date
Last billing total fee
Current plan price
Current per signature price
Current TW storage price
-}

{-

Nr of Users
Total nr of signatures	*
Total nr of signatures of finished docs (these are the ones we charge for)	*
Nr of docs with cross status	*
Nr of docs with blue status	*
Nr of docs with green status	*
Nr of docs yellow status	*
Nr of docs with orange status	*
Nr of docs with red status	*
Nr of docs with red exclamation mark status	*
Nr of friend invites	*
Nr of SkrivaPå staff invites *
Nr of Signups after finalized offer	TODO
Nr of Signups after finalized contract  TODO
-}

{-
Total nr of signatures
Total nr of signatures of finished docs (these are the ones we charge for)
Nr of docs with cross status
Nr of docs with blue status
Nr of docs with green status
Nr of docs with yellow status
Nr of docs with orange status
Nr of docs with red status
Nr of docs with red exclamation mark status
Nr of friend invites
-}


{-
User list:

Email
Name
Title
Company
Phone
Sales rep
Used signatures total
Used signatures last 1 month
Used signatures last 2 months
Used signatures last 3 months
Used signatures last 6 months
Used signatures last 12 months
-}

{- |
    Shows statistics about functionality use.

    If you would like to add some stats then please add the definitions to
    the getStatDefinitions function of whatever HasFunctionalityStats instance
    is relevant.
    The getStatDefinitions defines each statistic as a label and definition function
    pair.  The label will describe it in the table.  And the definition function
    takes in the doc, user or siglink, and has to return a bool to indicate whether
    that object uses the particular functionality.
    So you should add a pair to the list to add a statistic.
-}
showFunctionalityStats :: Kontrakcja m => m String
showFunctionalityStats = onlySalesOrAdmin $ do
  Context{ctxtime} <- getContext
  users <- dbQuery GetUsers
  (documents :: [Document]) <- return [] -- Hopefully fixed by Anton really soon! dbQuery GetAllDocuments
  adminFunctionalityStatsPage (mkStats ctxtime users)
                              (mkStats ctxtime documents)
  where
    mkStats :: HasFunctionalityStats a => MinutesTime -> [a] -> [(String, Int)]
    mkStats time xs =
      map (\(label, deffunc) -> (label, length $ filter (\x -> isRecent time x && deffunc x) xs)) getStatDefinitions

class HasFunctionalityStats a where
  isRecent :: MinutesTime -> a -> Bool
  getStatDefinitions :: [(String, a -> Bool)]

aRecentDate :: MinutesTime -> MinutesTime
aRecentDate = ((30 * 3) `daysBefore`)

instance HasFunctionalityStats Document where
  isRecent time doc = aRecentDate time < documentctime doc
  getStatDefinitions =
    [ ("drag n drop", anyField hasPlacement)
    , ("custom fields", anyField isCustom)
    , ("custom sign order", any ((/=) (SignOrder 1) . signatorysignorder . signatorydetails) . documentsignatorylinks)
    , ("csv", isJust . msum . fmap signatorylinkcsvupload . documentsignatorylinks)
    ]
    where
      anyField p doc =
        any p . concatMap (signatoryfields . signatorydetails) $ documentsignatorylinks doc
      hasPlacement SignatoryField{sfPlacements} = not $ null sfPlacements
      isCustom SignatoryField{sfType} =
        case sfType of
          (CustomFT _ _) -> True
          _ -> False

instance HasFunctionalityStats User where
  isRecent time user =
    case userhasacceptedtermsofservice user of
      Just tostime -> aRecentDate time < tostime
      Nothing -> False
  getStatDefinitions = []


showDocuments ::  Kontrakcja m => m  String
showDocuments = onlySalesOrAdmin $ adminDocuments =<< getContext

jsonDocuments :: Kontrakcja m => m JSValue
jsonDocuments = onlySalesOrAdmin $ do

  params <- getListParamsNew
  let sorting    = docSortingFromParams params
      searching  = docSearchingFromParams params
      pagination = ((listParamsOffset params),(listParamsLimit params))
      filters    = []
      domain     = [DocumentsOfWholeUniverse]
      docsPageSize = 100

  allDocs <- dbQuery $ GetDocuments domain (searching ++ filters) sorting pagination

  let documents = PagedList { list       = allDocs
                            , params     = params
                            , pageSize   = docsPageSize
                            }
  runJSONGenT $ do
            valueM "list" $ forM (take docsPageSize $ list documents) $ \doc-> runJSONGenT $ do
                 object "fields" $ do
                   value "id" $ show $ documentid doc
                   value "ctime" $ showMinutesTimeForAPI $ documentctime doc
                   value "mtime" $ showMinutesTimeForAPI $ documentmtime doc
                   object "author" $ do
                          value "name" $ getAuthorName doc
                          value "email" $ maybe "" getEmail $ getAuthorSigLink doc
                          value "company" $ maybe "" getCompanyName $ getAuthorSigLink doc
                   value "title"  $ documenttitle doc
                   value "status" $ take 20 $ show $ documentstatus doc
                   value "type"   $ show $ documenttype doc
                   value "signs"  $ map (getSmartName) $ documentsignatorylinks doc
            value "paging" $  pagingParamsJSON documents

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
    x "ctime"             = [Asc DocumentOrderByCTime]
    x "ctimeREV"          = [Desc DocumentOrderByCTime]
    x "signs"             = [Asc DocumentOrderByPartners]
    x "signsREV"          = [Desc DocumentOrderByPartners]
    x "process"           = [Asc DocumentOrderByProcess]
    x "processREV"        = [Desc DocumentOrderByProcess]
    x "type"              = [Asc DocumentOrderByType]
    x "typeREV"           = [Desc DocumentOrderByType]
    x "author"            = [Asc DocumentOrderByAuthor]
    x "authorRev"         = [Desc DocumentOrderByAuthor]
    x _                   = []


docSearchingFromParams :: ListParams -> [DocumentFilter]
docSearchingFromParams params =
  case listParamsSearching params of
    "" -> []
    x -> [DocumentFilterByString x]


handleBackdoorQuery :: Kontrakcja m => String -> m String
handleBackdoorQuery email = onlySalesOrAdmin $ onlyBackdoorOpen $ do
  minfo <- listToMaybe . reverse <$> dbQuery GetEmailsBySender email
  return $ maybe "No email found" mailContent minfo

sendInviteAgain :: Kontrakcja m => m KontraLink
sendInviteAgain = onlySalesOrAdmin $ do
  uid <- guardJustM $ readField "userid"
  user <- guardJustM $ dbQuery $ GetUserByID uid
  sendNewUserMail user
  addFlashM flashMessageNewActivationLinkSend
  return LoopBack

-- This method can be used do reseal a document
resealFile :: Kontrakcja m => DocumentID -> m KontraLink
resealFile docid = onlyAdmin $ do
  Log.debug $ "Trying to reseal document "++ show docid ++" | Only superadmin can do that"
  ctx <- getContext
  actor <- guardJust $ mkAdminActor ctx
  _ <- dbUpdate $ InsertEvidenceEvent
          ResealedPDF
          (F.value "actor" (actorWho actor))
          (Just docid)
          actor
  doc <- do
    doc' <- guardJustM $ dbQuery $ GetDocumentByDocumentID docid
    when_ (isDocumentError doc') $ do
       guardTrueM $ dbUpdate $ FixClosedErroredDocument docid actor
    guardJustM  $ dbQuery $ GetDocumentByDocumentID docid
  res <- sealDocument doc
  case res of
      Left  _ -> Log.debug "We failed to reseal the document"
      Right _ -> Log.debug "Ok, so the document has been resealed"
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
    Log.debug $ "location: " ++ location
    if "/" `isSuffixOf` location
     then do
      document <- guardJustM . dbQuery $ GetDocumentByDocumentID documentid
      r <- renderTemplate "daveDocument" $ do
        F.value "daveBody" $  inspectXML document
        F.value "id" $ show documentid
        F.value "closed" $ documentstatus document == Closed
        F.value "couldBeclosed" $ isDocumentError document && all (isSignatory =>>^ hasSigned) (documentsignatorylinks document)
      return $ Right r
     else return $ Left $ LinkDaveDocument documentid

{- |
   Used by super users to inspect a particular signatory link.
-}
daveSignatoryLink :: Kontrakcja m => DocumentID -> SignatoryLinkID -> m  String
daveSignatoryLink documentid siglinkid = onlyAdmin $ do
    document <- guardJustM . dbQuery $ GetDocumentByDocumentID documentid
    siglink <- guardJust $ getSigLinkFor document siglinkid
    renderTemplate  "daveSignatoryLink" $ do
        F.value "daveBody" $ inspectXML siglink
        F.value "docid" $ show documentid
        F.value "slid" $ show siglinkid
        F.objects "fields" $ for (signatoryfields $ signatorydetails siglink) $ \sf -> do
            F.value "fieldname" $ fieldTypeToString (sfType sf)
            F.value "fieldvalue" $ sfValue sf
            F.value "label" $ show $ sfType sf
      where fieldTypeToString sf = case sf of
              FirstNameFT      -> "sigfstname"
              LastNameFT       -> "sigsndname"
              EmailFT          -> "sigemail"
              CompanyFT        -> "sigco"
              PersonalNumberFT -> "sigpersnr"
              CompanyNumberFT  -> "sigcompnr"
              SignatureFT      -> "signature"
              CustomFT label _ -> "Custom: " ++ label
              CheckboxOptionalFT label -> "Checkbox*: " ++ label
              CheckboxObligatoryFT label -> "Checkbox: " ++ label

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
daveCompany :: Kontrakcja m => CompanyID -> m String
daveCompany companyid = onlyAdmin $ do
  company <- guardJustM $ dbQuery $ GetCompany companyid
  return $ inspectXML company
