module AppConf (
    AppConf(..)
  , AmazonConfig
  , unjsonAppConf
  ) where

import Data.Unjson
import Data.Word
import qualified Data.Text as T

import Database.Redis.Configuration
import EID.CGI.GRP.Config
import EID.Nets.Config
import FileStorage.Amazon.Config
import GuardTime (GuardTimeConf(..))
import HubSpot.Conf (HubSpotConf(..))
import Log.Configuration
import Monitoring (MonitoringConf(..))
import PdfToolsLambda.Conf
import Salesforce.Conf
import User.Email

-- | Main application configuration.  This includes amongst other
-- things the http port number, AWS, GuardTime, E-ID and email
-- configuraton, as well as a handy boolean indicating whether this is
-- a production or development instance.
data AppConf = AppConf {
    httpBindAddress    :: (Word32, Word16)
    -- ^ TCP address to bind to and port to listen on (0x7f000001,
    -- 8000) localhost:8000 (default) (0, 80) all interfaces port 80.
  , mainDomainUrl      :: String               -- ^ base url of the main domain
  , useHttps           :: Bool                 -- ^ should we redirect to https?
  , amazonConfig       :: AmazonConfig
  -- ^ AWS configuration (host, port, bucket, access key, secret key).
  -- The host and port default to S3.
  , dbConfig           :: T.Text               -- ^ postgresql configuration
  , maxDBConnections   :: Int                  -- ^ limit of db connections
  , queryTimeout       :: Maybe Int            -- ^ timeout for DB queries
  , redisCacheConfig   :: Maybe RedisConfig    -- ^ redis configuration
  , localFileCacheSize :: Int                  -- ^ size of local cache for files
  , logConfig          :: LogConfig            -- ^ logging configuration
  , production         :: Bool
    -- ^ production flag, enables some production stuff, disables some
    -- development stuff
  , cdnBaseUrl         :: Maybe String         -- ^ for CDN content in prod mode
  , guardTimeConf      :: GuardTimeConf
  , isMailBackdoorOpen :: Bool
    -- ^ If true allows admins to access last mail send. Used by
    -- selenium.
  , mailNoreplyAddress   :: String             -- ^ Noreply address used when sending email
  , cgiGrpConfig       :: Maybe CgiGrpConfig   -- ^ CGI GRP (E-ID) configuration
  , admins             :: [Email]
    -- ^ E-mail addresses of people regarded as admins.
  , sales              :: [Email]
    -- ^ E-mail addresses of people regarded as sales admins.
  , initialUsers       :: [(Email,String)]
    -- ^ E-mail and passwords for initial users.
  , mixpanelToken      :: Maybe String         -- ^ For mixpanel integration.
  , gaToken            :: Maybe String         -- ^ For Google Analytics integration.
  , trackjsToken       :: Maybe String         -- ^ For Track.js integration.
  , hubspotConf        :: Maybe HubSpotConf    -- ^ For Hubspot integration.
  , salesforceConf     :: Maybe SalesforceConf -- ^ Configuration of Salesforce.
  , netsConfig         :: Maybe NetsConfig
    -- ^ Configuration of Nets - .DK/.NO BankID provider.
  , monitoringConfig   :: Maybe MonitoringConf
    -- ^ Configuration of the ekg-statsd-based monitoring.
  , isAPILogEnabled :: Bool
    -- ^ If true, (limited amount of) API calls are logged in DB and available
    --   for user to inspect.
  , netsSignConfig     :: Maybe NetsSignConfig
    -- ^ Configuration of Nets for ESigning (BankID, NemID, ...)
  , pdfToolsLambdaConf :: PdfToolsLambdaConf
    -- ^ Configuration of PdfTools Lambda
  } deriving (Eq, Show)

unjsonAppConf :: UnjsonDef AppConf
unjsonAppConf = objectOf $ pure AppConf
  <*> (pure (,)
         <*> fieldDefBy "bind_ip" 0
            (fst . httpBindAddress)
            "IP to listen on, defaults to 0.0.0.0"
            unjsonIPv4AsWord32
         <*> field "bind_port"
            (snd . httpBindAddress)
            "Port to listen on")
  <*> field "main_domain_url"
      mainDomainUrl
      "Base URL of the main domain"
  <*> fieldDef "https" True
      useHttps
      "Should use https"
  <*> field "amazon"
      amazonConfig
      "Amazon configuration"
  <*> field "database"
      dbConfig
      "Database connection string"
  <*> field "max_db_connections"
      maxDBConnections
      "Database connections limit"
  <*> fieldOpt "query_timeout"
      queryTimeout
      "Query timeout in miliseconds"
  <*> fieldOpt "redis_cache"
      redisCacheConfig
      "Redis cache configuration"
  <*> field "local_file_cache_size"
      localFileCacheSize
      "Local file cache size in bytes"
  <*> field "logging"
      logConfig
      "Logging configuration"
  <*> fieldDef "production" False
      production
      "Is this production server"
  <*> fieldOpt "cdn_base_url"
      cdnBaseUrl
      "CDN base URL"
  <*> field "guardtime"
      guardTimeConf
      "GuardTime configuration"
  <*> fieldDef "mail_backdoor_open" False
      isMailBackdoorOpen
      "Enabling mails backdoor for test"
  <*> field "mail_noreply_address"
      mailNoreplyAddress
      "Noreply address used when sending email"
  <*> fieldOpt "cgi_grp"
      cgiGrpConfig
      "CGI GRP (E-ID) configuration"
  <*> field "admins"
      admins
      "email addresses of people regarded as admins"
  <*> field "sales"
      sales
      "email addresses of people regarded as sales admins"
  <*> field "initial_users"
      initialUsers
      "email and passwords for initial users"
  <*> fieldOpt "mixpanel"
      mixpanelToken
      "Token for Mixpanel"
  <*> fieldOpt "googleanalytics"
      gaToken
      "Token for Google Analytics"
  <*> fieldOpt "trackjs"
      trackjsToken
      "API Token for Track.js"
  <*> fieldOpt "hubspot"
      hubspotConf
      "Configuration of HubSpot"
  <*> fieldOpt "salesforce"
      salesforceConf
      "Configuration of salesforce"
  <*> fieldOpt "nets"
      netsConfig
      "Configuration of Nets - NO BankID, DN NemID provider"
  <*> fieldOpt "monitoring"
      monitoringConfig
      "Configuration of the ekg-statsd-based monitoring."
  <*> fieldDef "api_call_log_enabled" False
      isAPILogEnabled
      "Enable API Call logging in DB."
  <*> fieldOpt "nets_sign"
      netsSignConfig
      "Configuration of Nets for ESigning"
  <*> field "pdftools_lambda"
      pdfToolsLambdaConf
      "Configuration of PdfTools Lambda"

instance Unjson AppConf where
  unjsonDef = unjsonAppConf
