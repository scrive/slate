{- |
   Initialises contexts and sessions, and farms requests out to the appropriate handlers.
 -}
module AppControl
    ( module AppConf
    , staticRoutes
    , appHandler
    , AppGlobals(..)
    , defaultAWSAction

    -- exported for the sake of unit tests
    , handleLoginPost
    , getDocumentLocale
    , getUserLocale
    , signupPagePost
    ) where

import AppConf
import API.IntegrationAPI
import API.Service.Model
import API.Service.ServiceControl
import API.UserAPI
import API.MailAPI

import ActionSchedulerState
import AppView as V
import DB.Classes
import Doc.DocState
import InputValidation
import Kontra
import KontraLink
import Mails.MailsConfig
import Mails.SendGridEvents
import Mails.SendMail
import MinutesTime
import Misc
--import PayEx.PayExInterface ()-- Import so at least we check if it compiles
import Redirect
import Routing
import Happstack.StaticRouting(Route, choice, dir, path, param, remainingPath)
import Session
import Templates.Templates
import User.Model
import User.UserView as UserView
import qualified Stats.Control as Stats
import qualified Administration.AdministrationControl as Administration
import qualified AppLogger as Log (error, security, debug)
import qualified Contacts.ContactsControl as Contacts
import qualified Doc.DocControl as DocControl
import qualified Archive.Control as ArchiveControl
import qualified ELegitimation.Routes as Elegitimation
import qualified FlashMessage as F
import qualified MemCache
import qualified Payments.PaymentsControl as Payments
import qualified TrustWeaver as TW
import qualified User.UserControl as UserControl
import Util.FlashUtil
import Util.HasSomeUserInfo
import Util.KontraLinkUtils
import Doc.API

import Control.Concurrent
import Control.Monad.Error
import Data.Functor
import Data.List
import Data.Maybe
import Database.HDBC
import Database.HDBC.PostgreSQL
import GHC.Int (Int64(..))
import Happstack.Server hiding (simpleHTTP, host, dir, path)
import Happstack.Server.Internal.Cookie
import Happstack.State (query, update)
import Network.Socket
import System.Directory
import System.Time

import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as BSL
import qualified Data.ByteString.Lazy.UTF8 as BSL
import qualified Data.ByteString.UTF8 as BS
import qualified Data.Map as Map
import qualified Network.AWS.AWSConnection as AWS
import qualified Network.AWS.Authentication as AWS
import qualified Network.HTTP as HTTP
import Util.MonadUtils


{- |
  Global application data
-}
data AppGlobals
    = AppGlobals { templates       :: MVar (ClockTime, KontrakcjaGlobalTemplates)
                 , filecache       :: MemCache.MemCache FileID BS.ByteString
                 , mailer          :: Mailer
                 , appbackdooropen    :: Bool --whether a backdoor used to get email content is open or not
                 , docscache       :: MVar (Map.Map FileID JpegPages)
                 , esenforcer      :: MVar ()
                 }

{- |
   The routing table for the app.
   Routes in this table should be of the form
   dir "segment1" $ dir "segment2" $ .. $ dir "segmentn" $ hgetx $ handler
   OR
   dir "segment1" $ dir "segment2" $ .. $ dir "segmentn" $ hpostx $ handler

   param "name" is also allowed, which will guard based on the
   existence of a post/get param

   No other logic should be in here and no similar logic should be in the handler.
   That is, all routing logic should be in this table to ensure that we can find
   the function for any given path and method.
-}
staticRoutes :: Route (Kontra Response)
staticRoutes = choice
     [ allLocaleDirs $ const $ hGetAllowHttp $ handleHomepage
     , hGetAllowHttp $ getContext >>= (redirectKontraResponse . LinkHome . ctxlocale)

     , publicDir "priser" "pricing" LinkPriceplan handlePriceplanPage
     , publicDir "sakerhet" "security" LinkSecurity handleSecurityPage
     , publicDir "juridik" "legal" LinkLegal handleLegalPage
     , publicDir "sekretesspolicy" "privacy-policy" LinkPrivacyPolicy handlePrivacyPolicyPage
     , publicDir "allmana-villkor" "terms" LinkTerms handleTermsPage
     , publicDir "om-scrive" "about" LinkAbout handleAboutPage
     , publicDir "partners" "partners" LinkPartners handlePartnersPage -- FIXME: Same dirs for two languages is broken
     , publicDir "kunder" "clients" LinkClients handleClientsPage
     , publicDir "kontakta" "contact" LinkContactUs handleContactUsPage
     -- sitemap
     , dir "webbkarta"       $ hGetAllowHttp $ handleSitemapPage
     , dir "sitemap"         $ hGetAllowHttp $ handleSitemapPage

     -- this is SMTP to HTTP gateway
     , mailAPI
     , Elegitimation.handleRoutes
     , dir "s" $ hGet $ toK0 $ sendRedirect $ LinkContracts
     , dir "s" $ hGet $ toK3 $ DocControl.handleSignShow
     , dir "s" $ hGet $ toK4 $ DocControl.handleAttachmentDownloadForViewer --  FIXME: Shadowed by ELegitimation.handleRoutes; This will be droped


     , dir "s" $ param "sign"           $ hPostNoXToken $ toK3 $ DocControl.signDocument
     , dir "s" $ param "cancel"         $ hPostNoXToken $ toK3 $ DocControl.rejectDocument
     , dir "s" $ param "acceptaccount"  $ hPostNoXToken $ toK5 $ DocControl.handleAcceptAccountFromSign
     , dir "s" $ param "declineaccount" $ hPostNoXToken $ toK5 $ DocControl.handleDeclineAccountFromSign
     , dir "s" $ param "sigattachment"  $ hPostNoXToken $ toK3 $ DocControl.handleSigAttach
     , dir "s" $ param "deletesigattachment" $ hPostNoXToken $ toK3 $ DocControl.handleDeleteSigAttach

     , dir "sv" $ hGet $ toK3 $ DocControl.handleAttachmentViewForViewer

     --Q: This all needs to be done by author. Why we dont check it
     --here? MR

     --A: Because this table only contains routing logic. The logic of
     --what it does/access control is left to the handler. EN
     , dir "upload" $ hGet $ toK0 $ DocControl.handleShowUploadPage
     , dir "locale" $ hPost $ toK0 $ UserControl.handlePostUserLocale
     , dir "a"                     $ hGet  $ toK0 $ ArchiveControl.showAttachmentList
     , dir "a" $ param "archive"   $ hPost $ toK0 $ ArchiveControl.handleAttachmentArchive
     , dir "a" $ param "share"     $ hPost $ toK0 $ DocControl.handleAttachmentShare
     , dir "a" $ dir "rename"      $ hPost $ toK1 $ DocControl.handleAttachmentRename
     , dir "a"                     $ hPost $ toK0 $ DocControl.handleCreateNewAttachment

     , dir "t" $ hGet  $ toK0 $ ArchiveControl.showTemplatesList
     , dir "t" $ param "archive" $ hPost $ toK0 $ ArchiveControl.handleTemplateArchive
     , dir "t" $ param "share" $ hPost $ toK0 $ DocControl.handleTemplateShare
     , dir "t" $ param "template" $ hPost $ toK0 $ DocControl.handleCreateFromTemplate
     , dir "t" $ hPost $ toK0 $ DocControl.handleCreateNewTemplate

     , dir "o" $ hGet $ toK0 $ ArchiveControl.showOfferList
     , dir "o" $ param "archive" $ hPost $ toK0 $ ArchiveControl.handleOffersArchive
     , dir "o" $ param "remind" $ hPost $ toK0 $ DocControl.handleBulkOfferRemind

     , dir "or" $ hGet  $ toK0 $ ArchiveControl.showOrdersList
     , dir "or" $ param "archive" $ hPost $ toK0 $ ArchiveControl.handleOrdersArchive
     , dir "or" $ param "remind" $ hPost $ toK0 $ DocControl.handleBulkOrderRemind

     , dir "r" $ hGet $ toK0 $ ArchiveControl.showRubbishBinList
     , dir "r" $ param "restore" $ hPost $ toK0 $ DocControl.handleRubbishRestore
     , dir "r" $ param "reallydelete" $ hPost $ toK0 $ DocControl.handleRubbishReallyDelete

     , dir "d"                     $ hGet  $ toK2 $ DocControl.handleAttachmentDownloadForAuthor -- This will be droped and unified to one below
                                                                                                 -- FIXME: Shadowed by ELegitimation.handleRoutes

     , dir "d"                     $ hGet  $ toK3 $ DocControl.handleDownloadFileLogged -- This + magic hash version will be the only file download possible
     , dir "d"                     $ hGet  $ toK5 $ DocControl.handleDownloadFileNotLogged

     , dir "d"                     $ hGet  $ toK0 $ ArchiveControl.showContractsList
     , dir "d"                     $ hGet  $ toK1 $ DocControl.handleIssueShowGet
     , dir "d"                     $ hGet  $ toK2 $ DocControl.handleIssueShowTitleGet -- FIXME: Shadowed by DocControl.handleAttachmentDownloadForAuthor
     , dir "d"                     $ hGet  $ toK4 $ DocControl.handleIssueShowTitleGetForSignatory
     , dir "d" $ {- param "doc" $ -} hPost $ toK0 $ DocControl.handleIssueNewDocument
     , dir "d" $ param "archive"   $ hPost $ toK0 $ ArchiveControl.handleContractArchive
     , dir "d" $ param "remind"    $ hPost $ toK0 $ DocControl.handleBulkContractRemind
     , dir "d"                     $ hPost $ toK1 $ DocControl.handleIssueShowPost
     , dir "docs"                  $ hGet  $ toK0 $ DocControl.jsonDocumentsList
     , dir "doc"                   $ hGet  $ toK1 $ DocControl.jsonDocument
     , dir "mailpreview"           $ hGet  $ toK2 $ DocControl.prepareEmailPreview

     , dir "friends"               $ hGet  $ toK0 $ UserControl.handleFriends
     , dir "companyaccounts"       $ hGet  $ toK0 $ UserControl.handleCompanyAccounts

     , dir "df"                    $ hGet  $ toK2 $ DocControl.handleFileGet
     , dir "dv"                    $ hGet  $ toK1 $ DocControl.handleAttachmentViewForAuthor

     --This are actions on documents. We may integrate it with all the stuff above, but I don't like it. MR
     , dir "resend"  $ hPost $ toK2 $ DocControl.handleResend
     , dir "changeemail" $ hPost $ toK2 $ DocControl.handleChangeSignatoryEmail
     -- , dir "withdrawn" $ hPost $ DocControl.handleWithdrawn
     , dir "restart" $ hPost $ toK1 $ DocControl.handleRestart
     , dir "cancel"  $ hPost $ toK1 $ DocControl.handleCancel

     , dir "pages"  $ hGetAjax $ toK3 $ DocControl.showPage
     , dir "pages"  $ hGetAjax $ toK5 $ DocControl.showPageForSignatory
     -- HTMP emails can have embedded preview image
     , dir "preview" $ hGet $ toK2 $ DocControl.showPreview
     , dir "preview" $ hGet $ toK4 $ DocControl.showPreviewForSignatory

     , dir "template"  $ hPost $ toK0 $ DocControl.handleCreateFromTemplate

     , dir "filepages" $ hGetAjax $  toK2 $ DocControl.handleFilePages
     , dir "pagesofdoc" $ hGetAjax $ toK1 $ DocControl.handlePageOfDocument
     , dir "pagesofdoc" $ hGetAjax $ toK3 $ DocControl.handlePageOfDocumentForSignatory

     , dir "csvlandpage" $ hGet $ toK1 $ DocControl.handleCSVLandpage

     -- UserControl
     , dir "account"                    $ hGet  $ toK0 $ UserControl.handleUserGet
     , dir "account"                    $ hPost $ toK0 $ UserControl.handleUserPost
     , dir "account" $ dir "companyaccounts" $ hGet  $ toK0 $ UserControl.handleGetCompanyAccounts
     , dir "account" $ dir "companyaccounts" $ hPost $ toK0 $ UserControl.handlePostCompanyAccounts
     , dir "account" $ dir "sharing" $ hGet $ toK0 $ UserControl.handleGetSharing
     , dir "account" $ dir "sharing" $ hPost $ toK0 $ UserControl.handlePostSharing
     , dir "account" $ dir "security" $ hGet $ toK0 $ UserControl.handleGetUserSecurity
     , dir "account" $ dir "security" $ hPost $ toK0 $ UserControl.handlePostUserSecurity
     , dir "account" $ dir "mailapi" $ hGet $ toK0 $ UserControl.handleGetUserMailAPI
     , dir "account" $ dir "mailapi" $ hPost $ toK0 $ UserControl.handlePostUserMailAPI
     , dir "account" $ dir "bsa" $ hGet $ toK1 $ UserControl.handleGetBecomeCompanyAccount
     , dir "account" $ dir "bsa" $ hPost $ toK1 $ UserControl.handlePostBecomeCompanyAccount
     , dir "contacts"  $ hGet  $ toK0 $ Contacts.showContacts
     , dir "contacts"  $ hPost $ toK0 $ Contacts.handleContactsChange
     , dir "accepttos" $ hGet  $ toK0 $ UserControl.handleAcceptTOSGet
     , dir "accepttos" $ hPost $ toK0 $ UserControl.handleAcceptTOSPost

     -- super user only
     , dir "stats"      $ hGet  $ toK0 $ Administration.showStats
     , dir "createuser" $ hPost $ toK0 $ Administration.handleCreateUser
     , dir "sendgrid" $ dir "events" $ remainingPath POST $ handleSendgridEvent
     , dir "adminonly" $ hGet $ toK0 $ Administration.showAdminMainPage
     , dir "adminonly" $ dir "advuseradmin" $ hGet $ toK0 $ Administration.showAdminUserAdvanced
     , dir "adminonly" $ dir "useradminforsales" $ hGet $ toK0 $ Administration.showAdminUsersForSales
     , dir "adminonly" $ dir "useradminforpayments" $ hGet $ toK0 $ Administration.showAdminUsersForPayments
     , dir "adminonly" $ dir "useradmin" $ hGet $ toK1 $ Administration.showAdminUsers . Just
     , dir "adminonly" $ dir "useradmin" $ hGet $ toK0 $ Administration.showAdminUsers Nothing
     , dir "adminonly" $ dir "useradmin" $ dir "usagestats" $ hGet $ toK1 $ Stats.showAdminUserUsageStats
     , dir "adminonly" $ dir "useradmin" $ hPost $ toK1 $ Administration.handleUserChange
     , dir "adminonly" $ dir "companyadmin" $ hGet $ toK1 $ Administration.showAdminCompanies . Just
     , dir "adminonly" $ dir "companyadmin" $ hGet $ toK0 $ Administration.showAdminCompanies Nothing
     , dir "adminonly" $ dir "companyadmin" $ dir "users" $ hGet $ toK1 $ Administration.showAdminCompanyUsers
     , dir "adminonly" $ dir "companyadmin" $ dir "users" $ hPost $ toK1 $ Administration.handleCreateCompanyUser
     , dir "adminonly" $ dir "companyadmin" $ dir "usagestats" $ hGet $ toK1 $ Stats.showAdminCompanyUsageStats
     , dir "adminonly" $ dir "companyadmin" $ hPost $ toK1 $ Administration.handleCompanyChange
     , dir "adminonly" $ dir "functionalitystats" $ hGet $ toK0 $ Administration.showFunctionalityStats
     , dir "adminonly" $ dir "db" $ remainingPath GET $ https $ msum
               [ Administration.indexDB >>= toResp
               , onlySuperUser $ serveDirectory DisableBrowsing [] "_local/kontrakcja_state"
               ]

     , dir "adminonly" $ dir "documents" $ hGet $ toK0 $ Administration.showDocumentsDaylyList

     , dir "adminonly" $ dir "allstatscsv" $ path GET id $ Stats.handleDocStatsCSV
     , dir "adminonly" $ dir "userstatscsv" $ path GET id $ Stats.handleUserStatsCSV

     , dir "adminonly" $ dir "runstatsonalldocs" $ hGet $ toK0 $ Stats.addAllDocsToStats
     , dir "adminonly" $ dir "stats1to2" $ hGet $ toK0 $ Stats.handleMigrate1To2

     , dir "adminonly" $ dir "runstatsonallusers" $ hGet $ toK0 $ Stats.addAllUsersToStats

     , dir "adminonly" $ dir "cleanup"           $ hPost $ toK0 $ Administration.handleDatabaseCleanup
     , dir "adminonly" $ dir "statistics"        $ hGet  $ toK0 $ Stats.showAdminSystemUsageStats
     , dir "adminonly" $ dir "skrivapausers.csv" $ hGet  $ toK0 $ Administration.getUsersDetailsToCSV
     , dir "adminonly" $ dir "payments"          $ hGet  $ toK0 $ Payments.handlePaymentsModelForViewView
     , dir "adminonly" $ dir "advpayments"       $ hGet  $ toK0 $ Payments.handlePaymentsModelForEditView
     , dir "adminonly" $ dir "advpayments"       $ hPost $ toK0 $ Payments.handleAccountModelsChange

     , dir "adminonly" $ dir "services" $ hGet $ toK0 $ Administration.showServicesPage
     , dir "adminonly" $ dir "services" $ param "create" $ hPost $ toK0 $ Administration.handleCreateService
     , dir "adminonly" $ dir "translations" $ hGet $ toK0 $ Administration.showAdminTranslations

     -- a temporary service to help migration
     --, dir "adminonly" $ dir "migratesigaccounts" $ hGet $ toK0 $ Administration.migrateSigAccounts
     --, dir "adminonly" $ dir "migratecompanies" $ hGet $ toK0 $ Administration.migrateCompanies

     , dir "adminonly" $ dir "sysdump" $ hGet $ toK0 $ Administration.sysdump

     , dir "adminonly" $ dir "reseal" $ hPost $ toK1 $ Administration.resealFile
     , dir "adminonly" $ dir "replacemainfile" $ hPost $ toK1 $ Administration.replaceMainFile

     , dir "adminonly" $ dir "docproblems" $ hGet $ toK0 $ DocControl.handleInvariantViolations

     , dir "adminonly" $ dir "backdoor" $ hGet $ toK1 $ Administration.handleBackdoorQuery

     -- this stuff is for a fix
     , dir "adminonly" $ dir "510bugfix" $ hGet $ toK0 $ Administration.handleFixForBug510
     , dir "adminonly" $ dir "adminonlybugfix" $ hGet $ toK0 $ Administration.handleFixForAdminOnlyBug

     , dir "adminonly" $ dir "siglinkids_test_uniqueness" $ hGet $ toK0 $ Administration.handleCheckSigLinkIDUniqueness

     , dir "services" $ hGet $ toK0 $ handleShowServiceList
     , dir "services" $ hGet $ toK1 $ handleShowService
     , dir "services" $ dir "ui" $ hPost $ toK1 $ handleChangeServiceUI
     , dir "services" $ dir "password" $ hPost $ toK1 $ handleChangeServicePassword
     , dir "services" $ dir "settings" $ hPost $ toK1 $ handleChangeServiceSettings
     , dir "services" $ dir "logo" $ hGet $ toK1 $ handleServiceLogo
     , dir "services" $ dir "buttons_body" $ hGet $ toK1 $ handleServiceButtonsBody
     , dir "services" $ dir "buttons_rest" $ hGet $ toK1 $ handleServiceButtonsRest

     -- never ever use this
     , dir "adminonly" $ dir "neveruser" $ dir "resetservicepassword" $ hGetWrap (onlySuperUser . https) $ toK2 $ handleChangeServicePasswordAdminOnly

     , dir "adminonly" $ dir "log" $ hGetWrap (onlySuperUser . https) $ toK1 $ Administration.serveLogDirectory


     , dir "dave" $ dir "document" $ hGet $ toK1 $ Administration.daveDocument
     , dir "dave" $ dir "user"     $ hGet $ toK1 $ Administration.daveUser
     , dir "dave" $ dir "company"  $ hGet $ toK1 $ Administration.daveCompany

     -- account stuff
     , dir "logout"      $ hGet  $ toK0 $ handleLogout
     , allLocaleDirs $ const $ dir "login" $ hGet  $ toK0 $ handleLoginGet
     , allLocaleDirs $ const $ dir "login" $ hPostNoXToken $ toK0 $ handleLoginPost
     --, dir "signup"      $ hGet  $ signupPageGet
     , dir "signup"      $ hPostAllowHttp $ toK0 $ signupPagePost
     --, dir "vip"         $ hGet  $ signupVipPageGet
     --, dir "vip"         $ hPostNoXToken $ signupVipPagePost
     , dir "amnesia"     $ hPostNoXToken $ toK0 $ forgotPasswordPagePost
     , dir "amnesia"     $ hGet $ toK2 $ UserControl.handlePasswordReminderGet
     , dir "amnesia"     $ hPostNoXToken $ toK2 UserControl.handlePasswordReminderPost
     , dir "accountsetup"  $ hGet $ toK2 $ UserControl.handleAccountSetupGet
     , dir "accountsetup"  $ hPostNoXToken $ toK2 $ UserControl.handleAccountSetupPost
     , dir "accountremoval" $ hGet $ toK2 $ UserControl.handleAccountRemovalGet
     , dir "accountremoval" $ hPostNoXToken $ toK2 $ UserControl.handleAccountRemovalPost

     -- viral invite
     , dir "invite"      $ hPostNoXToken $ toK0 $ UserControl.handleViralInvite
     , dir "question"    $ hPostAllowHttp $ toK0 $ UserControl.handleQuestion

     -- someone wants a phone call
     , dir "phone" $ hPostAllowHttp $ toK0 $ UserControl.handlePhoneCallRequest

     -- a general purpose blank page
     --, dir "/blank" $ hGet $ toK0 $ simpleResponse ""

     , userAPI
     , integrationAPI
     , documentApi
     -- static files
     , remainingPath GET $ msum
         [ allowHttp $ serveHTMLFiles
         , allowHttp $ serveDirectory DisableBrowsing [] "public"
         ]
     ]

{- |
    This is a helper function for routing a public dir.
-}
publicDir :: String -> String -> (Locale -> KontraLink) -> Kontra Response -> Route (Kontra Response)
publicDir swedish english link handler = choice [
    -- the correct url with region/lang/publicdir where the publicdir must be in the correct lang
    allLocaleDirs $ \locale -> dirByLang locale swedish english $ hGetAllowHttp $ handler

    -- if they use the swedish name without region/lang we should redirect to the correct swedish locale
  , dir swedish $ hGetAllowHttp $ redirectKontraResponse $ link (mkLocaleFromRegion REGION_SE)

    -- if they use the english name without region/lang we should redirect to the correct british locale
  , dir english $ hGetAllowHttp $ redirectKontraResponse $ link (mkLocaleFromRegion REGION_GB)
  ]

{- |
    If the current request is referring to a document then this will
    return the locale of that document.
-}
getDocumentLocale :: (ServerMonad m, MonadIO m) => m (Maybe Locale)
getDocumentLocale = do
  rq <- askRq
  let docids = catMaybes . map (fmap fst . listToMaybe . reads) $ rqPaths rq
  mdoclocales <- mapM (DocControl.getDocumentLocale . DocumentID) docids
  return . listToMaybe $ catMaybes mdoclocales

{- |
    Determines the locale of the current user (whether they are logged in or not), by checking
    their settings, the request, and cookies.
-}
getUserLocale :: (MonadPlus m, MonadIO m, ServerMonad m, FilterMonad Response m, Functor m, HasRqData m) =>
                   Connection -> Maybe User -> m Locale
getUserLocale conn muser = do
  rq <- askRq
  currentcookielocale <- optional (readCookieValue "locale")
  activationlocale <- getActivationLocale rq
  let userlocale = locale <$> usersettings <$> muser
      urlregion = (listToMaybe $ rqPaths rq) >>= regionFromCode
      urllang = (listToMaybe . drop 1 $ rqPaths rq) >>= langFromCode
      urllocale = case (urlregion, urllang) of
                    (Just region, Just lang) -> Just $ mkLocale region lang
                    _ -> Nothing
  doclocale <- getDocumentLocale
  let browserlocale = getBrowserLocale rq
  let newlocale = firstOf [ activationlocale
                          , userlocale
                          , doclocale
                          , urllocale
                          , currentcookielocale
                          , Just browserlocale
                          ]
  let newlocalecookie = mkCookie "locale" (show newlocale)
  addCookie (MaxAge (60*60*24*366)) newlocalecookie
  return newlocale
  where
    getBrowserLocale rq =
      mkLocaleFromRegion $ regionFromHTTPHeader (fromMaybe "" $ BS.toString <$> getHeader "Accept-Language" rq)
    -- try and get the locale from the current activation user by checking the path for action ids, and giving them a go
    getActivationLocale rq = do
      let actionids = catMaybes . map (fmap fst . listToMaybe . reads) $ rqPaths rq
      mactionlocales <- mapM (getActivationLocaleFromAction . ActionID) actionids
      return . listToMaybe $ catMaybes mactionlocales
    getActivationLocaleFromAction aid = do
      maction <- query $ GetAction aid
      mactionuser <- case fmap actionType maction of
                       Just (AccountCreatedBySigning _ uid _ _) -> ioRunDB conn . dbQuery $ GetUserByID uid
                       Just (AccountCreated uid _) -> ioRunDB conn . dbQuery $ GetUserByID uid
                       _ -> return Nothing
      return $ fmap (locale . usersettings) mactionuser
    optional c = (liftM Just c) `mplus` (return Nothing)
    firstOf :: Bounded a => [Maybe a] -> a
    firstOf opts =
      case find isJust opts of
        Just val -> fromJust val
        Nothing -> defaultValue

forAllTargetedLocales :: (Locale -> Route h) -> Route h
forAllTargetedLocales r = choice (map r targetedLocales)

allLocaleDirs :: (Locale -> Route a) -> Route a
allLocaleDirs r = forAllTargetedLocales $ \l -> regionDir l $ langDir l $ r l

regionDir :: Locale -> Route a -> Route a
regionDir = dir . codeFromRegion . getRegion

langDir :: Locale -> Route a -> Route a
langDir = dir . codeFromLang . getLang

dirByLang :: HasLocale l => l -> String -> String -> Route a -> Route a
dirByLang locale swedishdir englishdir
  | getLang locale == LANG_SE = dir swedishdir
  | otherwise = dir englishdir

handleHomepage :: Kontra (Either Response (Either KontraLink String))
handleHomepage = do
  ctx@Context{ ctxmaybeuser,ctxservice } <- getContext
  loginOn <- isFieldSet "logging"
  referer <- getField "referer"
  email   <- getField "email"
  case (ctxmaybeuser, ctxservice) of
    (Just _user, _) -> do
      response <- V.simpleResponse =<< firstPage ctx loginOn referer email
      clearFlashMsgs
      return $ Left response
    (Nothing, Nothing) -> do
      response <- V.simpleResponse =<< firstPage ctx loginOn referer email
      clearFlashMsgs
      return $ Left response
    _ -> Left <$> embeddedErrorPage

handleSitemapPage :: Kontra Response
handleSitemapPage = handleWholePage sitemapPage

handlePriceplanPage :: Kontra Response
handlePriceplanPage = handleWholePage priceplanPage

handleSecurityPage :: Kontra Response
handleSecurityPage = handleWholePage securityPage

handleLegalPage :: Kontra Response
handleLegalPage = handleWholePage legalPage

handlePrivacyPolicyPage :: Kontra Response
handlePrivacyPolicyPage = handleWholePage privacyPolicyPage

handleTermsPage :: Kontra Response
handleTermsPage = handleWholePage termsPage

handleAboutPage :: Kontra Response
handleAboutPage = handleWholePage aboutPage

handlePartnersPage :: Kontra Response
handlePartnersPage = handleWholePage partnersPage

handleClientsPage :: Kontra Response
handleClientsPage = handleWholePage clientsPage

handleContactUsPage :: Kontra Response
handleContactUsPage = handleWholePage contactUsPage

handleWholePage :: Kontra String -> Kontra Response
handleWholePage f = do
  content <- f
  response <- V.simpleResponse content
  clearFlashMsgs
  return response

{- |
    Handles an error by displaying the home page with a modal error dialog.
-}
handleError :: Kontra Response
handleError = do
    ctx <- getContext
    case (ctxservice ctx) of
         Nothing -> do
            addFlashM V.modalError
            linkmain <- getHomeOrUploadLink
            sendRedirect linkmain
         Just _ -> embeddedErrorPage

{- |
   Creates a default amazon configuration based on the
   given AppConf
-}
defaultAWSAction :: AppConf -> AWS.S3Action
defaultAWSAction appConf =
    let (bucket,accessKey,secretKey) = maybe ("","","") id (amazonConfig appConf)
    in
    AWS.S3Action
           { AWS.s3conn = AWS.amazonS3Connection accessKey secretKey
           , AWS.s3bucket = bucket
           , AWS.s3object = ""
           , AWS.s3query = ""
           , AWS.s3metadata = []
           , AWS.s3body = BSL.empty
           , AWS.s3operation = HTTP.GET
           }


maybeReadTemplates :: MVar (ClockTime, KontrakcjaGlobalTemplates)
                      -> IO KontrakcjaGlobalTemplates
maybeReadTemplates mvar = modifyMVar mvar $ \(modtime, templates) -> do
        modtime' <- getTemplatesModTime
        if modtime /= modtime'
            then do
                Log.debug $ "Reloading templates"
                templates' <- readGlobalTemplates
                return ((modtime', templates'), templates')
            else return ((modtime, templates), templates)

showNamedHeader :: forall t . (t, HeaderPair) -> [Char]
showNamedHeader (_nm,hd) = BS.toString (hName hd) ++ ": [" ++
                      concat (intersperse ", " (map (show . BS.toString) (hValue hd))) ++ "]"

showNamedCookie :: ([Char], Cookie) -> [Char]
showNamedCookie (name,cookie) = name ++ ": " ++ mkCookieHeader Nothing cookie

showNamedInput :: ([Char], Input) -> [Char]
showNamedInput (name,input) = name ++ ": " ++ case inputFilename input of
                                                  Just filename -> filename
                                                  _ -> case inputValue input of
                                                           Left _tmpfilename -> "<<content in /tmp>>"
                                                           Right value -> show (BSL.toString value)

showRequest :: Request -> Maybe [([Char], Input)] -> [Char]
showRequest rq maybeInputsBody =
    show (rqMethod rq) ++ " " ++ rqUri rq ++ rqQuery rq ++ "\n" ++
    "post variables:\n" ++
    maybe "" (unlines . map showNamedInput) maybeInputsBody ++
    "http headers:\n" ++
    (unlines $ map showNamedHeader (Map.toList $ rqHeaders rq)) ++
    "http cookies:\n" ++
    (unlines $ map showNamedCookie (rqCookies rq))

{- |
   Creates a context, routes the request, and handles the session.
-}
appHandler :: Kontra Response -> AppConf -> AppGlobals -> ServerPartT IO Response
appHandler handleRoutes appConf appGlobals = do
  startTime <- liftIO getClockTime

  let quota :: GHC.Int.Int64 = 10000000

  temp <- liftIO $ getTemporaryDirectory
  decodeBody (defaultBodyPolicy temp quota quota quota)

  rq <- askRq

  session <- handleSession
  ctx <- createContext rq session
  response <- handle rq session ctx
  finishTime <- liftIO getClockTime
  let TOD ss sp = startTime
      TOD fs fp = finishTime
      _diff = (fs - ss) * 1000000000000 + fp - sp
  --Log.debug $ "Response time " ++ show (diff `div` 1000000000) ++ "ms"
  return response
  where
    handle :: Request -> Session -> Context -> ServerPartT IO Response
    handle rq session ctx = do
      (res,ctx') <- toIO ctx . runKontra $
         do
          res <- handleRoutes  `mplus` do
             rqcontent <- liftIO $ tryTakeMVar (rqInputsBody rq)
             when (isJust rqcontent) $
                 liftIO $ putMVar (rqInputsBody rq) (fromJust rqcontent)
             Log.error $ showRequest rq rqcontent
             response <- handleError
             setRsCode 404 response
          ctx' <- getContext
          return (res,ctx')

      let newsessionuser = fmap userid $ ctxmaybeuser ctx'
      let newflashmessages = ctxflashmessages ctx'
      let newelegtrans = ctxelegtransactions ctx'
      F.updateFlashCookie (aesConfig appConf) (ctxflashmessages ctx) newflashmessages
      updateSessionWithContextData session newsessionuser newelegtrans
      when (ctxdbconnclose ctx') $
        liftIO $ disconnect $ ctxdbconn ctx'
      return res

    createContext rq session = do
      hostpart <- getHostpart
      -- FIXME: we should read some headers from upstream proxy, if any
      let peerhost = case getHeader "x-real-ip" rq of
                       Just name -> BS.toString name
                       Nothing -> fst (rqPeer rq)

      -- rqPeer hostname comes always from showHostAddress
      -- so it is a bunch of numbers, just read them out
      -- getAddrInfo is strange that it can throw exceptions
      -- if exception is thrown, whole page load fails with
      -- error notification
      let hints = defaultHints { addrFlags = [AI_ADDRCONFIG, AI_NUMERICHOST] }
      addrs <- liftIO $ getAddrInfo (Just hints) (Just peerhost) Nothing
      let addr = head addrs
      let peerip = case addrAddress addr of
                     SockAddrInet _ hostip -> hostip
                     _ -> 0

      conn <- liftIO $ connectPostgreSQL $ dbConfig appConf
      minutestime <- liftIO getMinutesTime
      muser <- getUserFromSession conn session
      mcompany <- getCompanyFromSession conn session
      location <- getLocationFromSession session
      mservice <- ioRunDB conn . dbQuery . GetServiceByLocation . toServiceLocation =<< currentLink
      flashmessages <- withDataFn F.flashDataFromCookie $ maybe (return []) $ \fval ->
          case F.fromCookieValue (aesConfig appConf) fval of
               Just flashes -> return flashes
               Nothing -> do
                   Log.error $ "Couldn't read flash messages from value: " ++ fval
                   F.removeFlashCookie
                   return []

      -- do reload templates in non-production code
      templates2 <- liftIO $ maybeReadTemplates (templates appGlobals)

      -- work out the region and language
      doclocale <- getDocumentLocale
      userlocale <- getUserLocale conn muser

      let elegtrans = getELegTransactions session
          ctx = Context
                { ctxmaybeuser = muser
                , ctxhostpart = hostpart
                , ctxflashmessages = flashmessages
                , ctxtime = minutestime
                , ctxnormalizeddocuments = docscache appGlobals
                , ctxipnumber = peerip
                , ctxdbconn = conn
                , ctxdbconnclose = True
                , ctxdocstore = docstore appConf
                , ctxs3action = defaultAWSAction appConf
                , ctxgscmd = gsCmd appConf
                , ctxproduction = production appConf
                , ctxbackdooropen = isBackdoorOpen $ mailsConfig appConf
                , ctxtemplates = localizedVersion userlocale templates2
                , ctxglobaltemplates = templates2
                , ctxlocale = userlocale
                , ctxlocaleswitch = isNothing $ doclocale
                , ctxesenforcer = esenforcer appGlobals
                , ctxtwconf = TW.TrustWeaverConf
                              { TW.signConf = trustWeaverSign appConf
                              , TW.adminConf = trustWeaverAdmin appConf
                              , TW.storageConf = trustWeaverStorage appConf
                              , TW.retries = 3
                              , TW.timeout = 60000
                              }
                , ctxelegtransactions = elegtrans
                , ctxfilecache = filecache appGlobals
                , ctxxtoken = getSessionXToken session
                , ctxcompany = mcompany
                , ctxservice = mservice
                , ctxlocation = location
                , ctxadminaccounts = admins appConf
                , ctxdbconnstring = dbConfig appConf
                }
      return ctx

{- |
   Handles submission of the password reset form
-}
forgotPasswordPagePost :: Kontrakcja m => m KontraLink
forgotPasswordPagePost = do
  ctx <- getContext
  memail <- getOptionalField asValidEmail "email"
  case memail of
    Nothing -> return LoopBack
    Just email -> do
      muser <- runDBQuery $ GetUserByEmail Nothing $ Email email
      case muser of
        Nothing -> do
          Log.security $ "ip " ++ (show $ ctxipnumber ctx) ++ " made a failed password reset request for non-existant account " ++ (BS.toString email)
          return LoopBack
        Just user -> do
          now <- liftIO getMinutesTime
          minv <- checkValidity now <$> (query $ GetPasswordReminder $ userid user)
          case minv of
            Just Action{ actionID, actionType = PasswordReminder { prToken, prRemainedEmails, prUserID } } ->
              case prRemainedEmails of
                0 -> addFlashM flashMessageNoRemainedPasswordReminderEmails
                n -> do
                  -- I had to make it PasswordReminder because it was complaining about not giving cases
                  -- for the constructors of ActionType
                  _ <- update $ UpdateActionType actionID (PasswordReminder { prToken          = prToken
                                                                            , prRemainedEmails = n - 1
                                                                            , prUserID         = prUserID})
                  sendResetPasswordMail ctx (LinkPasswordReminder actionID prToken) user
            _ -> do -- Nothing or other ActionTypes (which should not happen)
              link <- newPasswordReminderLink user
              sendResetPasswordMail ctx link user
          addFlashM flashMessageChangePasswordEmailSend
          return LinkUpload

sendResetPasswordMail :: Kontrakcja m => Context -> KontraLink -> User -> m ()
sendResetPasswordMail ctx link user = do
  mail <- UserView.resetPasswordMail (ctxhostpart ctx) user link
  scheduleEmailSendout (ctxesenforcer ctx) $ mail { to = [getMailAddress user] }

{- |
   Handles viewing of the signup page
-}
_signupPageGet :: Kontra Response
_signupPageGet = do
    ctx <- getContext
    content <- liftIO (signupPageView $ ctxtemplates ctx)
    V.renderFromBody V.TopNone V.kontrakcja  content


_signupVipPageGet :: Kontra Response
_signupVipPageGet = do
    ctx <- getContext
    content <- liftIO (signupVipPageView $ ctxtemplates ctx)
    V.renderFromBody V.TopNone V.kontrakcja content
{- |
   Handles submission of the signup form.
   Normally this would create the user, (in the process mailing them an activation link),
   but if the user already exists, we check to see if they have accepted the tos.  If they haven't,
   then we send them a new activation link because probably the old one expired or was lost.
   If they have then we stop the signup.
-}
signupPagePost :: Kontrakcja m => m KontraLink
signupPagePost = do
    Context { ctxtime } <- getContext
    signup False $ Just ((60 * 24 * 31) `minutesAfter` ctxtime)

{-
    A comment next to LoopBack says never to use it. Is this function broken?
-}
signup :: Kontrakcja m => Bool -> Maybe MinutesTime -> m KontraLink
signup vip _freetill =  do
  ctx@Context{ctxhostpart} <- getContext
  memail <- getOptionalField asValidEmail "email"
  case memail of
    Nothing -> return LoopBack
    Just email -> do
      muser <- runDBQuery $ GetUserByEmail Nothing $ Email $ email
      case (muser, muser >>= userhasacceptedtermsofservice) of
        (Just user, Nothing) -> do
          -- there is an existing user that hasn't been activated, so resend the details
          al <- newAccountCreatedLink user
          mail <- newUserMail ctxhostpart email email al vip
          scheduleEmailSendout (ctxesenforcer ctx) $ mail { to = [MailAddress {fullname = email, email = email}] }
        (Nothing, Nothing) -> do
          -- this email address is new to the system, so create the user
          _mnewuser <- UserControl.createUser ctx (BS.empty, BS.empty) email Nothing Nothing vip
          return ()
        (_, _) -> return ()
      -- whatever happens we want the same outcome, we just claim we sent the activation link,
      -- because we don't want any security problems with user information leaks
      addFlashM $ modalUserSignupDone (Email email)
      return LoopBack

{- |
   Sends a new activation link mail, which is really just a new user mail.
-}
_sendNewActivationLinkMail:: Context -> User -> Kontra ()
_sendNewActivationLinkMail Context{ctxhostpart, ctxesenforcer} user = do
    let email = getEmail user
    al <- newAccountCreatedLink user
    mail <- newUserMail ctxhostpart email email al False
    scheduleEmailSendout ctxesenforcer $ mail { to = [MailAddress {fullname = email, email = email}] }

{- |
   Handles viewing of the login page
-}
handleLoginGet :: Kontrakcja m => m Response
handleLoginGet = do
  ctx <- getContext
  case ctxmaybeuser ctx of
       Just _  -> sendRedirect LinkUpload
       Nothing -> do
         referer <- getField "referer"
         email   <- getField "email"
         content <- V.pageLogin referer email
         V.renderFromBody V.TopNone V.kontrakcja content

{- |
   Handles submission of a login form.  On failure will redirect back to referer, if there is one.
-}
handleLoginPost :: Kontrakcja m => m KontraLink
handleLoginPost = do
    ctx <- getContext
    memail  <- getOptionalField asDirtyEmail    "email"
    mpasswd <- getOptionalField asDirtyPassword "password"
    let linkemail = maybe "" BS.toString memail
    case (memail, mpasswd) of
        (Just email, Just passwd) -> do
            -- check the user things here
            maybeuser <- runDBQuery $ GetUserByEmail Nothing (Email email)
            case maybeuser of
                Just user@User{userpassword}
                    | verifyPassword userpassword passwd -> do
                        Log.debug $ "User " ++ show email ++ " logged in"
                        _ <- runDBUpdate $ SetUserSettings (userid user) $ (usersettings user) {
                          locale = ctxlocale ctx
                        }
                        muuser <- runDBQuery $ GetUserByID (userid user)
                        logUserToContext muuser
                        return BackToReferer
                Just _ -> do
                        Log.debug $ "User " ++ show email ++ " login failed (invalid password)"
                        return $ LinkLogin (ctxlocale ctx) $ InvalidLoginInfo linkemail
                Nothing -> do
                    Log.debug $ "User " ++ show email ++ " login failed (user not found)"
                    return $ LinkLogin (ctxlocale ctx) $ InvalidLoginInfo linkemail
        _ -> return $ LinkLogin (ctxlocale ctx) $ InvalidLoginInfo linkemail

{- |
   Handles the logout, and sends user back to main page.
-}
handleLogout :: Kontrakcja m => m Response
handleLogout = do
    ctx <- getContext
    logUserToContext Nothing
    sendRedirect $ LinkHome (ctxlocale ctx)

{- |
   Serves out the static html files.
-}
serveHTMLFiles :: Kontra Response
serveHTMLFiles =  do
  rq <- askRq
  let fileName = last (rqPaths rq)
  guard ((length (rqPaths rq) > 0) && (isSuffixOf ".html" fileName))
  s <- guardJustM $ (liftIO $ catch (fmap Just $ BS.readFile ("html/" ++ fileName))
                                      (const $ return Nothing))
  renderFromBody V.TopNone V.kontrakcja $ BS.toString s

