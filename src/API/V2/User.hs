module API.V2.User (
    getAPIUser
  , getAPIUserWithPrivileges
  , getAPIUserWithAnyPrivileges
  , getAPIUserWithPad
) where

import Data.Text

import API.V2.Errors
import API.V2.Monad
import DB
import Kontra
import KontraPrelude
import OAuth.Model
import OAuth.Util
import User.Model
import Util.Actor

-- | Same as `getAPIUserWithPrivileges` but for only one `APIPrivilege`
getAPIUser :: Kontrakcja m => APIPrivilege -> m (User, Actor)
getAPIUser priv = getAPIUserWithPrivileges [priv]

-- | Get the User and Actor for the API, as long as any privileges are granted
-- Same behaviour as `getAPIUserWithPrivileges`
getAPIUserWithAnyPrivileges :: Kontrakcja m => m (User, Actor)
getAPIUserWithAnyPrivileges = getAPIUserWithPrivileges [APIPersonal, APIDocCheck, APIDocSend, APIDocCreate]

-- | Get the User and Actor for a API call
-- Either through:
-- 1. OAuth using the Authorization header
-- 2. Session for AJAX client (only if the Authorization header is empty)
--
-- Only returns if *any* of the privileges in privs are issued.
getAPIUserWithPrivileges :: Kontrakcja m => [APIPrivilege] -> m (User, Actor)
getAPIUserWithPrivileges privs = getAPIUserWith ctxmaybeuser privs

getAPIUserWithPad :: Kontrakcja m => APIPrivilege -> m (User, Actor)
getAPIUserWithPad priv = getAPIUserWith (\c -> ctxmaybeuser c `mplus` ctxmaybepaduser c) [priv]

-- * Interal functions

getAPIUserWith :: Kontrakcja m => (Context -> Maybe User) -> [APIPrivilege] -> m (User, Actor)
getAPIUserWith ctxUser privs = do
  moauthuser <- getOAuthUser privs
  case moauthuser of
    Just (Left msg) -> apiError $ invalidAuthorisationWithMsg (pack msg)
    Just (Right (user, actor)) -> return (user, actor)
    Nothing -> do
      msessionuser <- do
        ctx <- getContext
        case ctxUser ctx of
          Nothing -> return Nothing
          Just user -> return $ Just (user, authorActor ctx user)
      case msessionuser of
        Just (user, actor) -> return (user, actor)
        Nothing -> apiError invalidAuthorisation

getOAuthUser :: Kontrakcja m => [APIPrivilege] -> m (Maybe (Either String (User, Actor)))
getOAuthUser privs = do
  ctx <- getContext
  eauth <- getAuthorization
  case eauth of
    Nothing       -> return Nothing
    Just (Left l) -> return $ Just $ Left $ "OAuth headers could not be parsed: " ++ l
    Just (Right auth) -> do
      uap <- dbQuery $ GetUserIDForAPIWithPrivilege (oaAPIToken auth) (oaAPISecret auth) (oaAccessToken auth) (oaAccessSecret auth) privs
      case uap of
        Nothing -> return $ Just $ Left "OAuth credentials are invalid or they may not have sufficient privileges"
        Just (userid, apistring) -> do
          mUser <- dbQuery $ GetUserByID userid
          case mUser of
            Nothing -> apiError $ serverError "OAuth credentials are valid but the user account for those credentials does not exist"
            Just user -> do
              let actor = apiActor ctx user apistring
              return $ Just $ Right (user, actor)
