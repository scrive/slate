{-# LANGUAGE ExtendedDefaultRules #-}
{- |
   Defines the App level views.
-}
module AppView(
                renderFromBody
              , renderFromBodyWithFields
              , notFoundPage
              , internalServerErrorPage
              , simpleJsonResponse
              , simpleAesonResponse
              , simpleUnjsonResponse
              , simpleHtmlResponse
              , simpleHtmlResonseClrFlash
              , respondWithPDF
              , priceplanPage
              , unsupportedBrowserPage
              , standardPageFields
              , entryPointFields
              , companyForPage
              , companyUIForPage
              , handleTermsOfService
              , enableCookiesPage
              ) where

import Control.Arrow (second)
import Control.Monad.Catch
import Data.Char
import Data.String.Utils hiding (join)
import Data.Unjson
import Happstack.Server.SimpleHTTP
import Log
import Text.StringTemplates.Templates
import qualified Data.Aeson as A
import qualified Data.ByteString.Base16 as B16
import qualified Data.ByteString.Lazy as BSL
import qualified Data.ByteString.Lazy.UTF8 as BSL
import qualified Data.ByteString.UTF8 as BS
import qualified Data.Map as Map
import qualified Text.JSON as JSON
import qualified Text.StringTemplates.Fields as F

import Analytics.Include
import BrandedDomain.BrandedDomain
import Branding.Adler32
import Company.CompanyUI
import Company.Model
import DB
import FlashMessage
import Kontra
import KontraPrelude
import ThirdPartyStats.Core
import User.Lang
import User.Model
import Utils.HTTP
import Utils.Monoid
import Version

-- * Main Implementation

{- |
   Renders some page body xml into a complete reponse
-}
renderFromBody :: Kontrakcja m
               => String
               -> m Response
renderFromBody content = renderFromBodyWithFields content (return ())


{- |
   Renders some page body xml into a complete reponse. It can take aditional fields to be passed to a template
-}
renderFromBodyWithFields :: Kontrakcja m
               => String
               -> Fields m ()
               -> m Response
renderFromBodyWithFields content fields = do
  ctx <- getContext
  ad <- getAnalyticsData
  res <- simpleHtmlResponse =<< pageFromBody ctx ad content fields
  clearFlashMsgs
  return res


{- |
   Renders some page body xml into a complete page of xml
-}
pageFromBody :: Kontrakcja m
             => Context
             -> AnalyticsData
             -> String
             -> Fields m ()
             -> m String
pageFromBody ctx ad bodytext fields = do
  mcompanyui <- companyUIForPage
  renderTemplate "wholePage" $ do
    F.value "content" bodytext
    standardPageFields ctx mcompanyui ad
    F.valueM "httplink" $ getHttpHostpart
    fields

companyForPage  :: Kontrakcja m => m (Maybe Company)
companyForPage = do
  ctx <- getContext
  case (ctxmaybeuser ctx) of
       Nothing -> return Nothing
       Just user -> fmap Just $ dbQuery $ GetCompanyByUserID (userid user)

companyUIForPage  :: Kontrakcja m => m (Maybe CompanyUI)
companyUIForPage = do
  ctx <- getContext
  case (ctxmaybeuser ctx) of
       Just User{usercompany = cid} -> Just <$> (dbQuery $ GetCompanyUI cid)
       _ -> return Nothing

notFoundPage :: Kontrakcja m => m Response
notFoundPage = pageWhereLanguageCanBeInUrl $ do
  ctx <- getContext
  ad <- getAnalyticsData
  content <- if (bdMainDomain (ctxbrandeddomain ctx)||  isJust (ctxmaybeuser ctx))
   then renderTemplate "notFound" $ do
                    standardPageFields ctx Nothing ad
   else renderTemplate "notFoundWithoutHeaders" $ do
                    standardPageFields ctx Nothing ad
  simpleHtmlResonseClrFlash content

internalServerErrorPage :: Kontrakcja m => m Response
internalServerErrorPage =  pageWhereLanguageCanBeInUrl $ do
  ctx <- getContext
  ad <- getAnalyticsData
  content <- if (bdMainDomain (ctxbrandeddomain ctx)||  isJust (ctxmaybeuser ctx))
   then renderTemplate "internalServerError" $ do
                    standardPageFields ctx Nothing ad
   else renderTemplate "internalServerErrorWithoutHeaders" $ do
                    standardPageFields ctx Nothing ad
  simpleHtmlResonseClrFlash content

pageWhereLanguageCanBeInUrl :: Kontrakcja m => m Response -> m Response
pageWhereLanguageCanBeInUrl handler = do
  language <- fmap langFromCode <$> rqPaths <$> askRq
  case (language) of
       (Just lang:_) -> switchLang lang >> handler
       _ -> handler


priceplanPage :: Kontrakcja m => m Response
priceplanPage = do
  ctx <- getContext
  ad <- getAnalyticsData
  if( bdMainDomain $ ctxbrandeddomain ctx)
  then do
    content <- renderTemplate "priceplanPage" $ do
      standardPageFields ctx Nothing ad
    simpleHtmlResonseClrFlash content
  else respond404

unsupportedBrowserPage :: Kontrakcja m => m Response
unsupportedBrowserPage = do
  res <- renderTemplate "unsupportedBrowser" $ return ()
  simpleHtmlResponse res

enableCookiesPage :: Kontrakcja m => m Response
enableCookiesPage = do
  rq <- askRq
  let cookies = rqCookies rq
      headers = rqHeaders rq
      hostname = fst $ rqPeer rq
      ua = case Map.lookup "user-agent" headers of
             Just (HeaderPair _ (x:_)) -> BS.toString x
             _ -> "<unknown>"
  let cookieNames = show $ map fst cookies
      mixpanel event = asyncLogEvent (NamedEvent event) [ SomeProp "cookies" $ PVString cookieNames
                                                        , SomeProp "browser" $ PVString ua
                                                        , SomeProp "host" $ PVString hostname
                                                        ]
  logInfo "Current cookies" $ object [
      "cookies" .= map (second cookieToJson) cookies
    ]
  ctx <- getContext
  ad <- getAnalyticsData
  case cookies of
    [] -> do
      -- there are still no cookies, client probably disabled them
      mixpanel "Enable cookies page load"
      content <- renderTemplate "enableCookies" $ do
        standardPageFields ctx Nothing ad
      simpleHtmlResponse content
    _ -> do
      -- there are some cookies after all, so no point in telling them to enable them
      mixpanel "Enable cookies page load attempt with cookies"
      -- internalServerError is a happstack function, it's not our internalError
      -- this will not rollback the transaction
      let fields = standardPageFields ctx Nothing ad
      content <- if bdMainDomain (ctxbrandeddomain ctx) || isJust (ctxmaybeuser ctx)
                    then renderTemplate "sessionTimeOut" fields
                    else renderTemplate "sessionTimeOutWithoutHeaders" fields
      pageWhereLanguageCanBeInUrl $ simpleHtmlResonseClrFlash content >>= internalServerError
  where
    cookieToJson Cookie{..} = object [
        "version"   .= cookieVersion
      , "path"      .= cookiePath
      , "domain"    .= cookieDomain
      , "name"      .= cookieName
      , "value"     .= cookieValue
      , "secure"    .= secure
      , "http_only" .= httpOnly
      ]

handleTermsOfService :: Kontrakcja m => m Response
handleTermsOfService = withAnonymousContext $ do
  ctx <- getContext
  ad <- getAnalyticsData
  content <- if (bdMainDomain $ ctxbrandeddomain ctx)
                then do
                  renderTemplate "termsOfService" $ do
                    standardPageFields ctx Nothing ad
                else do
                  renderTemplate "termsOfServiceWithBranding" $ do
                    standardPageFields ctx Nothing ad
  simpleHtmlResonseClrFlash content

standardPageFields :: (TemplatesMonad m, MonadDB m, MonadThrow m) => Context -> Maybe CompanyUI -> AnalyticsData -> Fields m ()
standardPageFields ctx mcompanyui ad = do
  F.value "langcode" $ codeFromLang $ ctxlang ctx
  F.value "logged" $ isJust (ctxmaybeuser ctx)
  F.value "padlogged" $ isJust (ctxmaybepaduser ctx)
  case listToMaybe $ ctxflashmessages ctx of
    Just f -> F.object "flash" $ flashMessageFields f
    _ -> return ()
  F.value "hostpart" $ ctxDomainUrl ctx
  F.value "production" (ctxproduction ctx)
  F.value "brandingdomainid" (show . bdid . ctxbrandeddomain $ ctx)
  F.value "brandinguserid" (fmap (show . userid) (ctxmaybeuser ctx `mplus` ctxmaybepaduser ctx))
  F.value "ctxlang" $ codeFromLang $ ctxlang ctx
  F.object "analytics" $ analyticsTemplates ad
  F.value "trackjstoken" (ctxtrackjstoken ctx)
  F.valueM "brandinghash" $ brandingAdler32 ctx mcompanyui
  F.value "title" $ case emptyToNothing . strip =<< companyBrowserTitle =<< mcompanyui of
                      Just ctitle -> ctitle ++ " - " ++ (bdBrowserTitle $ ctxbrandeddomain ctx)
                      Nothing -> (bdBrowserTitle $ ctxbrandeddomain ctx)
  entryPointFields ctx

-- Official documentation states that JSON mime type is
-- 'application/json'. IE8 for anything that starts with
-- 'application/*' invokes 'Download file...' dialog box and does not
-- allow JavaScript XHR to see the response. Therefore we have to
-- ignore the standard and output something that matches 'text/*', we
-- use 'text/javascript' for this purpose.
--
-- If future we should return 'application/json' for all browsers
-- except for IE8. We do not have access to 'Agent' string at this
-- point though, so we go this hackish route for everybody.

jsonContentType :: BS.ByteString
jsonContentType = "text/plain; charset=utf-8"

simpleJsonResponse :: (JSON.JSON a, FilterMonad Response m) => a -> m Response
simpleJsonResponse = ok . toResponseBS jsonContentType . BSL.fromString . JSON.encode

simpleAesonResponse :: (A.ToJSON a, FilterMonad Response m) => a -> m Response
simpleAesonResponse = ok . toResponseBS jsonContentType . A.encode . A.toJSON

simpleUnjsonResponse :: (FilterMonad Response m) => UnjsonDef a -> a -> m Response
simpleUnjsonResponse unjson a = ok $ toResponseBS jsonContentType $ unjsonToByteStringLazy' (Options { pretty = True, indent = 2, nulls = True }) unjson a


{- |
   Changing our pages into reponses
-}
simpleHtmlResponse :: Kontrakcja m => String -> m Response
simpleHtmlResponse s = ok $ toResponseBS (BS.fromString "text/html;charset=utf-8") $ BSL.fromString s


{- | Sames as simpleHtmlResponse, but clears also flash messages and modals -}
simpleHtmlResonseClrFlash :: Kontrakcja m => String -> m Response
simpleHtmlResonseClrFlash rsp = do
  res <- simpleHtmlResponse rsp
  clearFlashMsgs
  return res

respondWithPDF :: Bool -> BS.ByteString -> Response
respondWithPDF forceDownload contents =
  setHeaderBS "Content-Type" "application/pdf" $
  (if forceDownload then setHeaderBS "Content-Disposition" "attachment" else id) $
  Response 200 Map.empty nullRsFlags (BSL.fromChunks [contents]) Nothing

{- |
   JavaScript entry points require version and cdnbaseurl to work.
   This variables are also required by standardHeaderContents template.
-}
entryPointFields :: TemplatesMonad m => Context -> Fields m ()
entryPointFields ctx =  do
  F.value "cdnbaseurl" (ctxcdnbaseurl ctx)
  F.value "versioncode" $ BS.toString $ B16.encode $ BS.fromString versionID


flashMessageFields :: (Monad m) => FlashMessage -> Fields m ()
flashMessageFields flash = do
  F.value "type" $  case flashType flash of
    OperationDone   -> ("success" :: String)
    OperationFailed -> ("error" :: String)
  F.value "message" $ replace "\"" "'" $ filter (not . isControl) $ flashMessage flash
