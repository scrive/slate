{-  Set fo handlers for manipulating themes. Used by other handlers, should not be used on their own - since they don't do any access control,
    except for theme ownership.

    IMPORTANT: No function from this module does access control. They should not be used on their own.
-}
module Theme.Control (
    handleGetTheme
  , handleGetThemesForUserGroup
  , handleGetThemesForDomain
  , handleGetThemesUsedByDomain
  , handleNewThemeForDomain
  , handleNewThemeForUserGroup
  , handleUpdateThemeForDomain
  , handleUpdateThemeForUserGroup
  , handleDeleteThemeForDomain
  , handleDeleteThemeForUserGroup
  ) where

import Data.Unjson
import Data.Unjson as Unjson
import Log
import qualified Data.Aeson as Aeson
import qualified Data.Text as T

import BrandedDomain.BrandedDomain
import BrandedDomain.Model
import DB
import Happstack.Fields
import Kontra
import Theme.Model
import Theme.View
import UserGroup.Data
import Util.MonadUtils

handleGetTheme:: Kontrakcja m => ThemeID -> m Aeson.Value
handleGetTheme tid =  do
  theme <- dbQuery $ GetTheme tid
  return $ Unjson.unjsonToJSON' (Options { pretty = True, indent = 2, nulls = True }) unjsonTheme theme

handleGetThemesForUserGroup:: Kontrakcja m => UserGroupID -> m Aeson.Value
handleGetThemesForUserGroup ugid =  do
  themes <- dbQuery $ GetThemesForUserGroup ugid
  return $ Unjson.unjsonToJSON' (Options { pretty = True, indent = 2, nulls = True }) unjsonThemesList themes

handleGetThemesForDomain:: Kontrakcja m => BrandedDomainID -> m Aeson.Value
handleGetThemesForDomain did =  do
  themes <- dbQuery $ GetThemesForDomain did
  return $ Unjson.unjsonToJSON'(Options { pretty = True, indent = 2, nulls = True }) unjsonThemesList themes

-- Generate list of themes used by given domain. Note that order is important here - but we don't need to introduce any middle structure.
handleGetThemesUsedByDomain:: Kontrakcja m => BrandedDomain -> m Aeson.Value
handleGetThemesUsedByDomain domain =  do
  mailTheme     <- dbQuery $ GetTheme $ get bdMailTheme     domain
  signviewTheme <- dbQuery $ GetTheme $ get bdSignviewTheme domain
  serviceTheme  <- dbQuery $ GetTheme $ get bdServiceTheme  domain
  return $ Unjson.unjsonToJSON'  (Options { pretty = True, indent = 2, nulls = True }) unjsonThemesList [mailTheme,signviewTheme,serviceTheme]

handleUpdateThemeForDomain:: Kontrakcja m => BrandedDomainID -> ThemeID -> m ()
handleUpdateThemeForDomain did tid =  do
  guardNotMainDomain did "Main domain themes can't be changed"
  theme <- dbQuery $ GetTheme tid
  themeJSON <- guardJustM $ getFieldBS "theme"
  case Aeson.eitherDecode themeJSON of
    Left err -> do
      logInfo "Error while parsing theme for domain" $ object [
          "error" .= err
        ]
      internalError
    Right js -> case (Unjson.parse unjsonTheme js) of
      (Result newTheme []) -> do
        _ <- dbUpdate $ UpdateThemeForDomain did newTheme {themeID = themeID theme}
        return ()
      _ -> internalError

handleUpdateThemeForUserGroup:: Kontrakcja m => UserGroupID -> ThemeID -> m ()
handleUpdateThemeForUserGroup ugid tid =  do
  theme <- dbQuery $ GetTheme tid
  themeJSON <- guardJustM $ getFieldBS "theme"
  case Aeson.eitherDecode themeJSON of
   Left err -> do
    logInfo "Error while parsing theme for user group" $ object [
        "error" .= err
      ]
    internalError
   Right js -> case (Unjson.parse unjsonTheme js) of
        (Result newTheme []) -> do
          _ <- dbUpdate $ UpdateThemeForUserGroup ugid newTheme {themeID = themeID theme}
          return ()
        _ -> internalError


handleNewThemeForDomain:: Kontrakcja m => BrandedDomainID -> ThemeID -> m Aeson.Value
handleNewThemeForDomain did tid = do
  guardNotMainDomain did "Can't create new themes for main domain"
  theme <- dbQuery $ GetTheme tid
  name <- guardJustM $ getField "name"
  newTheme <- dbUpdate $ InsertNewThemeForDomain did $ theme {themeName = name}
  return $ Unjson.unjsonToJSON' (Options { pretty = True, indent = 2, nulls = True }) unjsonTheme newTheme

handleNewThemeForUserGroup :: Kontrakcja m => UserGroupID -> ThemeID -> m Aeson.Value
handleNewThemeForUserGroup ugid tid = do
  theme <- dbQuery $ GetTheme tid
  name <- guardJustM $ getField "name"
  newTheme <- dbUpdate $ InsertNewThemeForUserGroup ugid $ theme {themeName = name}
  return $ Unjson.unjsonToJSON' (Options { pretty = True, indent = 2, nulls = True }) unjsonTheme newTheme

handleDeleteThemeForDomain:: Kontrakcja m => BrandedDomainID -> ThemeID -> m ()
handleDeleteThemeForDomain did tid = do
  guardNotMainDomain did  "Main domain themes can't be deleted"
  dbUpdate $ DeleteThemeOwnedByDomain did tid

handleDeleteThemeForUserGroup:: Kontrakcja m => UserGroupID -> ThemeID -> m ()
handleDeleteThemeForUserGroup ugid tid = do
  dbUpdate $ DeleteThemeOwnedByUserGroup ugid tid


guardNotMainDomain :: Kontrakcja m => BrandedDomainID -> T.Text -> m ()
guardNotMainDomain did msg = do
  bd <- dbQuery $ GetBrandedDomainByID did
  if (get bdMainDomain bd)
   then do
    logInfo_ msg
    internalError
   else return ()
