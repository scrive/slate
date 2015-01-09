{-# LANGUAGE ExtendedDefaultRules #-}
{- |
   Defines the App level views.
-}
module Branding.Control(
                handleServiceBranding
              , handleLoginBranding
              , handleDomainBranding
              , handleSignviewBranding
              , handleSignviewBrandingWithoutDocument
              , handleSignviewBrandingInternal
              , loginLogo
              , serviceLogo
              , emailLogo
              , emailLogoForSignatory
              , signviewLogo
              , signviewLogoWithoutDocument
              , faviconIcon
              ) where

import Control.Applicative
import Control.Monad
import Control.Monad.Trans
import Data.Maybe
import Happstack.Server.SimpleHTTP
import qualified Data.ByteString.Lazy as BSL
import qualified Data.ByteString.UTF8 as BS
import qualified Data.Map as Map

import BrandedDomain.BrandedDomain
import Branding.CSS
import Company.CompanyUI
import Company.Model
import DB
import Doc.DocStateData
import Doc.DocumentID
import Doc.Model.Query
import Doc.SignatoryLinkID
import Doc.Tokens.Model
import Kontra
import Theme.Model
import User.Model
import User.Utils
import Util.MonadUtils
import Util.SignatoryLinkUtils


handleServiceBranding :: Kontrakcja m => String -> String -> m Response
handleServiceBranding _ _ = do
  theme <- getServiceTheme
  brandingCSS <- liftIO $ serviceBrandingCSS theme
  let res = Response 200 Map.empty nullRsFlags brandingCSS Nothing
  return $ setHeaderBS (BS.fromString "Content-Type") (BS.fromString "text/css") res

getServiceTheme ::  Kontrakcja m =>  m Theme
getServiceTheme = do
  ctx <- getContext
  case (mplus (ctxmaybeuser ctx) (ctxmaybepaduser ctx)) of
       Just user -> do
         company <- getCompanyForUser user
         companyui <- dbQuery $ GetCompanyUI (companyid company)
         dbQuery $ GetTheme $ fromMaybe (bdServiceTheme $ ctxbrandeddomain ctx) (companyServiceTheme $ companyui)
       Nothing -> dbQuery $ GetTheme $ bdServiceTheme $ ctxbrandeddomain ctx


handleLoginBranding :: Kontrakcja m => String -> String -> m Response
handleLoginBranding _ _ = do
  theme <- getLoginTheme
  brandingCSS <- liftIO $ loginBrandingCSS theme
  let res = Response 200 Map.empty nullRsFlags brandingCSS Nothing
  return $ setHeaderBS (BS.fromString "Content-Type") (BS.fromString "text/css") res


getLoginTheme ::  Kontrakcja m =>  m Theme
getLoginTheme = do
  ctx <- getContext
  dbQuery $ GetTheme $ (bdLoginTheme $ ctxbrandeddomain ctx)

-- Generates domain branding - enything that is onlu branded at domain level - i.e colors of status icons
handleDomainBranding :: Kontrakcja m => String -> String-> m Response
handleDomainBranding _ _ = do
  ctx <- getContext
  brandingCSS <- liftIO $ domainBrandingCSS $ ctxbrandeddomain ctx
  let res = Response 200 Map.empty nullRsFlags brandingCSS Nothing
  return $ setHeaderBS (BS.fromString "Content-Type") (BS.fromString "text/css") res

-- Used to brand signview
handleSignviewBranding :: Kontrakcja m => DocumentID ->  SignatoryLinkID -> String -> String -> m Response
handleSignviewBranding did slid _ _ = do
  theme <- getSignviewTheme did slid
  brandingCSS <- liftIO $ signviewBrandingCSS theme
  let res = Response 200 Map.empty nullRsFlags brandingCSS Nothing
  return $ setHeaderBS (BS.fromString "Content-Type") (BS.fromString "text/css") res

getSignviewTheme ::  Kontrakcja m => DocumentID ->  SignatoryLinkID -> m Theme
getSignviewTheme did slid = do
  ctx <- getContext
  magichash <- guardJustM  $ dbQuery $ GetDocumentSessionToken slid
  doc <- dbQuery $ GetDocumentByDocumentID did
  sl <- guardJustM $ return $ getMaybeSignatoryLink (doc,slid)
  when (signatorymagichash sl /= magichash) $ internalError
  authorid <- guardJustM $ return $ getAuthorSigLink doc >>= maybesignatory
  user <- guardJustM $ dbQuery $ GetUserByIDIncludeDeleted authorid
  company <- getCompanyForUser user
  companyui <- dbQuery $ GetCompanyUI (companyid company)
  dbQuery $ GetTheme $ fromMaybe (bdSignviewTheme $ ctxbrandeddomain ctx) (companySignviewTheme $ companyui)


-- Used to brand some view with signview branding but without any particular document. It requires some user to be logged in.
handleSignviewBrandingWithoutDocument :: Kontrakcja m => String -> String -> m Response
handleSignviewBrandingWithoutDocument _ _ = do
  theme <- getSignviewThemeWithoutDocument
  brandingCSS <- liftIO $ signviewBrandingCSS theme
  let res = Response 200 Map.empty nullRsFlags brandingCSS Nothing
  return $ setHeaderBS (BS.fromString "Content-Type") (BS.fromString "text/css") res

getSignviewThemeWithoutDocument ::  Kontrakcja m =>  m Theme
getSignviewThemeWithoutDocument = do
  ctx <- getContext
  user <-  guardJust $ mplus (ctxmaybeuser ctx) (ctxmaybepaduser ctx)
  company <- getCompanyForUser user
  companyui <- dbQuery $ GetCompanyUI (companyid company)
  dbQuery $ GetTheme $ fromMaybe (bdSignviewTheme $ ctxbrandeddomain ctx) (companySignviewTheme $ companyui)


-- Used to brand signview with current logged in user service branding - if user entered document from archive, he should not be supprised by branding
handleSignviewBrandingInternal :: Kontrakcja m => String -> String -> m Response
handleSignviewBrandingInternal _ _ = do
  ctx <- getContext
  user <-  guardJust $ mplus (ctxmaybeuser ctx) (ctxmaybepaduser ctx)
  company <- getCompanyForUser user
  companyui <- dbQuery $ GetCompanyUI (companyid company)
  theme <- dbQuery $ GetTheme $ fromMaybe (bdServiceTheme $ ctxbrandeddomain ctx) (companyServiceTheme $ companyui)
  brandingCSS <- liftIO $ signviewBrandingCSS theme
  let res = Response 200 Map.empty nullRsFlags brandingCSS Nothing
  return $ setHeaderBS (BS.fromString "Content-Type") (BS.fromString "text/css") res

loginLogo :: Kontrakcja m => String  -> m Response
loginLogo _ = do
  tid <- bdLoginTheme <$> ctxbrandeddomain <$> getContext
  theme <- dbQuery $ GetTheme tid
  return $ setHeaderBS "Cache-Control" "max-age=31536000" $ setHeaderBS (BS.fromString "Content-Type") (BS.fromString "image/png") $
        Response 200 Map.empty nullRsFlags (BSL.fromChunks $ [unBinary $ themeLogo theme]) Nothing


serviceLogo :: Kontrakcja m => String  -> m Response
serviceLogo _ = do
  ctx <- getContext
  user <-  guardJust $ mplus (ctxmaybeuser ctx) (ctxmaybepaduser ctx)
  company <- getCompanyForUser user
  companyui <- dbQuery $ GetCompanyUI (companyid company)
  theme <- dbQuery $ GetTheme $ fromMaybe (bdServiceTheme $ ctxbrandeddomain ctx) (companyServiceTheme $ companyui)
  return $ setHeaderBS "Cache-Control" "max-age=31536000" $ setHeaderBS (BS.fromString "Content-Type") (BS.fromString "image/png") $
        Response 200 Map.empty nullRsFlags (BSL.fromChunks $ [unBinary $ themeLogo theme]) Nothing


emailLogo :: Kontrakcja m => String  -> m Response
emailLogo _ = do
  ctx <- getContext
  user <-  guardJust $ mplus (ctxmaybeuser ctx) (ctxmaybepaduser ctx)
  company <- getCompanyForUser user
  companyui <- dbQuery $ GetCompanyUI (companyid company)
  theme <- dbQuery $ GetTheme $ fromMaybe (bdMailTheme $ ctxbrandeddomain ctx) (companyMailTheme $ companyui)
  return $ setHeaderBS "Cache-Control" "max-age=31536000" $ setHeaderBS (BS.fromString "Content-Type") (BS.fromString "image/png") $
        Response 200 Map.empty nullRsFlags (BSL.fromChunks $ [unBinary $ themeLogo theme]) Nothing


emailLogoForSignatory :: Kontrakcja m => DocumentID -> SignatoryLinkID -> String  -> m Response
emailLogoForSignatory  did slid _ = do
  ctx <- getContext
  magichash <- guardJustM  $ dbQuery $ GetDocumentSessionToken slid
  doc <- dbQuery $ GetDocumentByDocumentID did
  sl <- guardJustM $ return $ getMaybeSignatoryLink (doc,slid)
  when (signatorymagichash sl /= magichash) $ internalError
  authorid <- guardJustM $ return $ getAuthorSigLink doc >>= maybesignatory
  user <- guardJustM $ dbQuery $ GetUserByIDIncludeDeleted authorid
  company <- getCompanyForUser user
  companyui <- dbQuery $ GetCompanyUI (companyid company)
  theme <- dbQuery $ GetTheme $ fromMaybe (bdMailTheme $ ctxbrandeddomain ctx) (companyMailTheme $ companyui)
  return $ setHeaderBS "Cache-Control" "max-age=31536000" $ setHeaderBS (BS.fromString "Content-Type") (BS.fromString "image/png") $
        Response 200 Map.empty nullRsFlags (BSL.fromChunks $ [unBinary $ themeLogo theme]) Nothing

signviewLogo :: Kontrakcja m => DocumentID -> SignatoryLinkID -> String  -> m Response
signviewLogo  did slid _ = do
  theme <- getSignviewTheme did slid
  return $ setHeaderBS "Cache-Control" "max-age=31536000" $ setHeaderBS (BS.fromString "Content-Type") (BS.fromString "image/png") $
        Response 200 Map.empty nullRsFlags (BSL.fromChunks $ [unBinary $ themeLogo theme]) Nothing


signviewLogoWithoutDocument :: Kontrakcja m => String  -> m Response
signviewLogoWithoutDocument _ = do
  theme <- getSignviewThemeWithoutDocument
  return $ setHeaderBS "Cache-Control" "max-age=31536000" $ setHeaderBS (BS.fromString "Content-Type") (BS.fromString "image/png") $
        Response 200 Map.empty nullRsFlags (BSL.fromChunks $ [unBinary $ themeLogo theme]) Nothing

faviconIcon :: Kontrakcja m => String  -> m Response
faviconIcon _ = do
  ctx <- getContext
  companyFavicon <- case (mplus (ctxmaybeuser ctx) (ctxmaybepaduser ctx)) of
    Nothing -> return Nothing
    Just user -> do
      company <- getCompanyForUser user
      companyui <- dbQuery $ GetCompanyUI (companyid company)
      return (companyFavicon $ companyui)
  let favicon = fromMaybe (bdFavicon $ ctxbrandeddomain ctx) companyFavicon
  return $ setHeaderBS "Cache-Control" "max-age=31536000" $ setHeaderBS (BS.fromString "Content-Type") (BS.fromString "image/png") $
        Response 200 Map.empty nullRsFlags (BSL.fromChunks $ [unBinary $ favicon]) Nothing
