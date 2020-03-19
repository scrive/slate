module Session.Model (
    getNonTempSessionID
  , getNonTempSessionIDWithTimeout
  , getCurrentSession
  , updateSession
  , getUserFromSession
  , getPadUserFromSession
  , getSession
  , getDocumentSessionTimeoutSecs
  , startNewSessionWithUser
  , terminateAllUserSessionsExceptCurrent
  , TerminateAllButOneUserSessions(..)
  , DeleteExpiredSessions(..)
  , PurgeExpiredTemporaryLoginTokens(..)
  , NewTemporaryLoginToken(..)
  -- Exported for tests
  , GetSession(..)
  ) where

import Control.Monad.Base
import Control.Monad.Catch
import Control.Monad.IO.Class
import Control.Monad.Trans.Maybe
import Crypto.RNG
import Data.Int
import Data.Ord (Down(..))
import Data.Time.Clock (addUTCTime, diffUTCTime)
import Happstack.Server hiding (Session)
import Log

import DB
import Doc.Model.Query (GetDocumentAuthorIDsBySignatoryLinkIDs(..))
import Doc.SignatoryLinkID (SignatoryLinkID)
import KontraMonad
import Log.Identifier
import MagicHash
import MinutesTime
import Session.Constant
import Session.Cookies
import Session.SessionID as SessionID
import Session.Types
import User.Model
import UserGroup.Model
import UserGroup.Types
import Utils.HTTP

-- Get session timeout from a user ID, checking for custom
-- timeout set in the user's group
getSessionTimeoutSecs :: forall  m . (MonadDB m, MonadThrow m) => UserID -> m Int32
getSessionTimeoutSecs userId =
  fromMaybe defaultSessionTimeoutSecs <$> getMaybeSessionTimeoutSecs userId

-- | Get the session timeout from the user's user group settings
getMaybeSessionTimeoutSecs
  :: forall  m . (MonadDB m, MonadThrow m) => UserID -> m (Maybe Int32)
getMaybeSessionTimeoutSecs userId = do
  ugwp <- dbQuery $ UserGroupGetWithParentsByUserID userId
  return $ ugwpSettings ugwp ^. #sessionTimeoutSecs

-- | Get the document session timeout - default one or custom if present
getDocumentSessionTimeoutSecs :: (MonadDB m, MonadThrow m) => UserID -> m Int32
getDocumentSessionTimeoutSecs userId =
  fmap (fromMaybe defaultSessionTimeoutSecs) (getMaybeDocumentSessionTimeoutSecs userId)

-- | Get the document session timeout from the user group settings of the document author.
getMaybeDocumentSessionTimeoutSecs
  :: (MonadDB m, MonadThrow m) => UserID -> m (Maybe Int32)
getMaybeDocumentSessionTimeoutSecs userId = do
  ugwp <- dbQuery $ UserGroupGetWithParentsByUserID userId
  return $ ugwpSettings ugwp ^. #documentSessionTimeoutSecs

-- | Get the session expiry delay used for extending the session's expiry date.
-- It's the user's custom session timeout or the document session timeout
-- (whichever is longer).
--
-- Defaults to maxSessionExpirationDelaySecs if those custom values are not set.
getSessionExpirationDelaySecs
  :: forall  m . (MonadDB m, MonadLog m, MonadThrow m) => Session -> m Int32
getSessionExpirationDelaySecs session = do
  mUserTimeout <- case sesUserID session `mplus` sesPadUserID session of
    Nothing     -> return Nothing
    Just userId -> getMaybeSessionTimeoutSecs userId

  docTimeouts <- do
    slids     <- dbQuery (GetSessionSignatoryLinkIDs $ sesID session)
    authorIds <- dbQuery (GetDocumentAuthorIDsBySignatoryLinkIDs slids)
    mTimeouts <- mapM getMaybeDocumentSessionTimeoutSecs authorIds
    return $ catMaybes mTimeouts

  let combinedTimeouts =
        map (min maxSessionExpirationDelaySecs) $ maybeToList mUserTimeout ++ docTimeouts

  -- Why multiple timeouts? We might have a case where a scrive user login
  -- session also includes a document token ...  or several document tokens. Or
  -- a situation where non-scrive user session includes multiple document
  -- tokens. Now which session timeout should we choose?  We decided that we
  -- should choose the longest session timeout.
  return . fromMaybe maxSessionExpirationDelaySecs $ safeMax combinedTimeouts
  where safeMax = listToMaybe . sortOn Down

-- Get the session expiry time for a user's new session relative
-- to the current time
getSessionExpiry
  :: forall  m . (MonadTime m, MonadDB m, MonadThrow m) => UserID -> m UTCTime
getSessionExpiry userId = do
  now        <- currentTime
  timeoutSec <- getSessionTimeoutSecs userId
  return $ timeoutSec `secondsAfter` now

getDefaultSessionExpiry :: forall  m . (MonadTime m, MonadDB m, MonadThrow m) => m UTCTime
getDefaultSessionExpiry = do
  now <- currentTime
  return $ defaultSessionTimeoutSecs `secondsAfter` now

-- | Get a non-temporary session ID from Context. If the current
-- session ID is temporary, insert a new empty session into the
-- database and return its ID (needed when the document ticket/eleg
-- transaction needs to be inserted into the database, but current
-- session is temporary), also modifying Context to carry modified ID.
getNonTempSessionID
  :: (CryptoRNG m, KontraMonad m, MonadDB m, MonadThrow m, MonadTime m, ServerMonad m)
  => m SessionID
getNonTempSessionID = getNonTempSessionIDWithTimeout defaultSessionTimeoutSecs

-- | A version of getNonTempSessionID that allows setting a session expiry timeout.
--   Added to support the custom document session feature (CORE-1975).
getNonTempSessionIDWithTimeout
  :: (CryptoRNG m, KontraMonad m, MonadDB m, MonadThrow m, MonadTime m, ServerMonad m)
  => Int32
  -> m SessionID
getNonTempSessionIDWithTimeout timeoutSecs = do
  sid <- view #sessionID <$> getContext
  if sid == SessionID.tempSessionID
    then do
      new_sid <- sesID <$> insertEmptySession
      modifyContext $ set #sessionID new_sid
      return new_sid
    else return sid
  where
    insertEmptySession = do
      sesToken     <- random
      sesCSRFToken <- random
      now          <- currentTime
      sesDomain    <- currentDomain
      let sesExpires = secondsAfter timeoutSecs now

      update . CreateSession $ Session
        { sesID        = SessionID.tempSessionID
        , sesUserID    = Nothing
        , sesPadUserID = Nothing
        , ..
        }

-- | Get the current session based on cookies set.
-- If no session is available, return a new empty session.
-- If current session is expiring, extend the session
-- expiry by 2 hours.

-- IE 10 is sending cookies for both domain and subdomain (scrive.com
-- & nj.scrive.com) We need to read them both, since we have no idea
-- which is the right one.
getCurrentSession
  :: ( CryptoRNG m
     , MonadDB m
     , MonadThrow m
     , ServerMonad m
     , MonadLog m
     , FilterMonad Response m
     , MonadIO m
     )
  => m Session
getCurrentSession = do
  bxt <- isXTokenCookieBroken
  if bxt
    then do
      emptySession
    else do
      cookieSessions <- currentSessionInfoCookies
      getSessionFromCookies cookieSessions
  where
    getSessionFromCookies (cs : css) = do
      domain <- currentDomain
      mses   <- getSession (cookieSessionID cs) (cookieSessionToken cs) domain
      case mses of
        Just ses -> return ses
        Nothing  -> getSessionFromCookies css
    getSessionFromCookies [] = emptySession

-- Create new session with provided user ID
startNewSessionWithUser
  :: forall m
   . ( FilterMonad Response m
     , ServerMonad m
     , MonadDB m
     , MonadLog m
     , MonadThrow m
     , MonadIO m
     , MonadBase IO m
     , CryptoRNG m
     )
  => UserID
  -> m Session
startNewSessionWithUser userId = do
  session <- emptySession
  deleteSuperfluousUserSessions userId
  expires <- getSessionExpiry userId
  let session1 = session { sesUserID = Just userId, sesExpires = expires }
  dbUpdate $ CreateSession session1

updateSession
  :: forall m
   . ( FilterMonad Response m
     , ServerMonad m
     , MonadDB m
     , MonadLog m
     , MonadThrow m
     , MonadIO m
     , MonadBase IO m
     )
  => Session
  -> SessionID
  -> Maybe UserID
  -> Maybe UserID
  -> m (Maybe Session)
updateSession session new_ses_id' new_muser' new_mpad_user' = do
  if new_ses_id' == SessionID.tempSessionID
    then handleNewSession session new_muser' new_mpad_user'
    else if sesID session == new_ses_id'
      then handleExistingSession session new_muser' new_mpad_user'
      else handleOverrideSession new_ses_id' new_muser' new_mpad_user'
  where
    handleNewSession :: Session -> Maybe UserID -> Maybe UserID -> m (Maybe Session)
    handleNewSession session1 new_muser new_mpad_user = do
      case mplus new_muser new_mpad_user of
        (Just userId) -> do
          deleteSuperfluousUserSessions userId
          expires <- getSessionExpiry userId
          let session2 = session1 { sesExpires   = expires
                                  , sesUserID    = new_muser
                                  , sesPadUserID = new_mpad_user
                                  }
          session3 <- dbUpdate $ CreateSession session2
          startSessionCookie session3
          return $ Just session3
        Nothing -> do
          fixSessionCookiesIfBrokenOrSessionExpired
          return Nothing

    handleExistingSession :: Session -> Maybe UserID -> Maybe UserID -> m (Maybe Session)
    handleExistingSession session1 new_muser new_mpad_user = do
      if sesUserID session1 /= new_muser || sesPadUserID session1 /= new_mpad_user
        then do

          expires <- case mplus new_muser' new_mpad_user' of
            (Just userId) -> do
              deleteSuperfluousUserSessions userId
              getSessionExpiry userId
            Nothing -> getDefaultSessionExpiry

          let session2 = session1 { sesExpires   = expires
                                  , sesUserID    = new_muser
                                  , sesPadUserID = new_mpad_user
                                  }

          success <- dbUpdate $ UpdateSession session2

          res     <- if success
            then return $ Just session2
            else do
              logInfo_
                "UpdateSession didn't update session\
              \ when it should have (existing session)"
              return Nothing

          when (isNothing new_muser && isNothing new_mpad_user) stopSessionCookie

          return res
        else return Nothing

    handleOverrideSession
      :: SessionID -> Maybe UserID -> Maybe UserID -> m (Maybe Session)
    handleOverrideSession new_ses_id new_muser new_mpad_user = do
      mses <- dbQuery $ GetSession new_ses_id
      case mses of
        Nothing -> do
          logInfo_ "updateSession failed while trying to switch session"
          return Nothing
        Just session1 -> do
          let session2 =
                session1 { sesUserID = new_muser, sesPadUserID = new_mpad_user }
          success <- dbUpdate $ UpdateSession session2
          if success
            then do
              startSessionCookie session2
              return $ Just session2
            else do
              logInfo_ "UpdateSession didn't update session when it should have had"
              return Nothing

getUserFromSession :: (MonadDB m, MonadThrow m) => Session -> m (Maybe User)
getUserFromSession Session { sesUserID } = case sesUserID of
  Just uid -> dbQuery $ GetUserByID uid
  Nothing  -> return Nothing

getPadUserFromSession :: (MonadDB m, MonadThrow m) => Session -> m (Maybe User)
getPadUserFromSession Session { sesPadUserID } = case sesPadUserID of
  Just uid -> dbQuery $ GetUserByID uid
  Nothing  -> return Nothing

getSession
  :: (MonadDB m, MonadLog m, MonadThrow m, MonadTime m)
  => SessionID
  -> MagicHash
  -> Text
  -> m (Maybe Session)
getSession sid token domain = runMaybeT $ do
  Just session1@Session {..} <- dbQuery $ GetSession sid
  guard $ sesToken == token
  guard $ sesDomain == domain
  now <- currentTime
  -- Updating 'expires' on every access is costly and results in
  -- quite a lot of database races for a single row in database, at
  -- least for user sessions.
  -- So we decided to update 'expires' only when at least 10% of the
  -- maxSessionExpirationDelaySecs is consumed
  if diffUTCTime sesExpires now < (0.9 * maxSessionExpirationDelaySecs)
    then do
    -- Get the actual session expiry delay from user group settings,
    -- which maybe shorter than maxSessionExpirationDelaySecs
      expiryDelay <- fromIntegral <$> getSessionExpirationDelaySecs session1
      let session2 = session1 { sesExpires = expiryDelay `addUTCTime` now }
      void . dbUpdate $ UpdateSession session2
      return session2
    else return session1

-- If there is session-id cookie but no xtoken cookie or session has expired
-- but we still get cookie, then lets just clean cookies.
fixSessionCookiesIfBrokenOrSessionExpired
  :: ( MonadDB m
     , MonadThrow m
     , ServerMonad m
     , MonadLog m
     , FilterMonad Response m
     , MonadIO m
     )
  => m ()
fixSessionCookiesIfBrokenOrSessionExpired = do
  brokenXTokenCookie <- isXTokenCookieBroken
  cookieSessions     <- currentSessionInfoCookies
  let someSessionCookieExists = not $ null cookieSessions
  allSessionsExpiredOrDropped <- and
    <$> forM cookieSessions (isExpiredOrDroppedSession . cookieSessionID)
  when (brokenXTokenCookie || (someSessionCookieExists && allSessionsExpiredOrDropped))
    $ do
        stopSessionCookie
  where
    isExpiredOrDroppedSession
      :: (MonadDB m, MonadThrow m, MonadTime m) => SessionID -> m Bool
    isExpiredOrDroppedSession sid = isNothing <$> dbQuery (GetSession sid)

terminateAllUserSessionsExceptCurrent
  :: ( CryptoRNG m
     , MonadDB m
     , MonadThrow m
     , ServerMonad m
     , MonadLog m
     , FilterMonad Response m
     , MonadIO m
     )
  => UserID
  -> m ()
terminateAllUserSessionsExceptCurrent uid = do
  cs <- getCurrentSession
  dbUpdate $ TerminateAllButOneUserSessions uid (sesID cs)

selectSessionSelectorsList :: [SQL]
selectSessionSelectorsList =
  ["id", "user_id", "pad_user_id", "expires", "token", "csrf_token", "domain"]

data DeleteExpiredSessions = DeleteExpiredSessions
instance (MonadDB m, MonadThrow m, MonadTime m) =>
  DBUpdate m DeleteExpiredSessions () where
  update DeleteExpiredSessions = do
    now <- currentTime
    (runQuery_ . sqlDelete "sessions") . sqlWhere $ "expires <" <?> now

data TerminateAllButOneUserSessions = TerminateAllButOneUserSessions UserID SessionID
instance (MonadDB m, MonadThrow m, MonadTime m) =>
  DBUpdate m TerminateAllButOneUserSessions () where
  update (TerminateAllButOneUserSessions uid sid) = do
    runQuery_ . sqlDelete "sessions" $ do
      sqlWhereAny [sqlWhere $ "user_id =" <?> uid, sqlWhere $ "pad_user_id =" <?> uid]
      sqlWhere $ "id <>" <?> sid

newtype GetSession = GetSession SessionID
instance (MonadDB m, MonadThrow m, MonadTime m) =>
  DBQuery m GetSession (Maybe Session) where
  query (GetSession sid) = do
    now <- currentTime
    runQuery_ . sqlSelect "sessions" $ do
      mapM_ sqlResult selectSessionSelectorsList
      sqlWhereEq "id" sid
      sqlWhere $ "expires >=" <?> now
    fetchMaybe fetchSession

newtype CreateSession = CreateSession Session
instance (MonadDB m, MonadThrow m) => DBUpdate m CreateSession Session where
  update (CreateSession Session {..}) = do
    runQuery_ . sqlInsert "sessions" $ do
      sqlSet "user_id"     sesUserID
      sqlSet "pad_user_id" sesPadUserID
      sqlSet "token"       sesToken
      sqlSet "csrf_token"  sesCSRFToken
      sqlSet "domain"      sesDomain
      sqlSet "expires"     sesExpires
      mapM_ sqlResult selectSessionSelectorsList
    fetchOne fetchSession

newtype UpdateSession = UpdateSession Session
instance (MonadDB m, MonadThrow m) => DBUpdate m UpdateSession Bool where
  update (UpdateSession Session {..}) = do
    runQuery01 . sqlUpdate "sessions" $ do
      sqlSet "user_id"     sesUserID
      sqlSet "pad_user_id" sesPadUserID
      sqlSet "token"       sesToken
      sqlSet "csrf_token"  sesCSRFToken
      sqlSet "domain"      sesDomain
      sqlSet "expires"     sesExpires
      sqlWhereEq "id" sesID

fetchSession
  :: (SessionID, Maybe UserID, Maybe UserID, UTCTime, MagicHash, MagicHash, Text)
  -> Session
fetchSession (sesID, sesUserID, sesPadUserID, sesExpires, sesToken, sesCSRFToken, sesDomain)
  = Session { .. }

data PurgeExpiredTemporaryLoginTokens = PurgeExpiredTemporaryLoginTokens
instance (MonadDB m, MonadTime m) => DBUpdate m PurgeExpiredTemporaryLoginTokens Int where
  -- Expired tokens should remain in the DB for 12h to provide better error messages
  update _ = do
    purgeTime <- ((12 * 60) `minutesBefore`) <$> currentTime
    runSQL $ "DELETE FROM temporary_login_tokens WHERE expiration_time <=" <?> purgeTime

data NewTemporaryLoginToken = NewTemporaryLoginToken UserID UTCTime
instance (CryptoRNG m, MonadDB m) => DBUpdate m NewTemporaryLoginToken MagicHash where
  update (NewTemporaryLoginToken uid expiryTime) = do
    hash <- random
    runQuery_ . sqlInsert "temporary_login_tokens" $ do
      sqlSet "hash"            hash
      sqlSet "user_id"         uid
      sqlSet "expiration_time" expiryTime
    return hash

newtype GetSessionSignatoryLinkIDs = GetSessionSignatoryLinkIDs SessionID
instance (MonadDB m, MonadThrow m)
  => DBQuery m GetSessionSignatoryLinkIDs [SignatoryLinkID] where
  query (GetSessionSignatoryLinkIDs sid) = do
    runQuery_ . sqlSelect "document_session_tokens" $ do
      sqlResult "document_session_tokens.signatory_link_id"
      sqlWhereEq "document_session_tokens.session_id" sid
    fetchMany runIdentity

-- | We allow for at most 51 sessions with the same user_id, so if there
-- are more, just delete the oldest ones. Note: only 50 sessions are left
-- because we do deletion BEFORE inserting new session. This is better
-- because this way we can be sure that newest session will always end
-- up in the database.
deleteSuperfluousUserSessions :: (MonadDB m, MonadLog m) => UserID -> m ()
deleteSuperfluousUserSessions uid = do
  n <-
    runQuery
    $   "DELETE FROM sessions WHERE id IN (SELECT id FROM sessions WHERE user_id ="
    <?> uid
    <+> "ORDER BY expires DESC OFFSET 50)"
  logInfo "Superfluous sessions of user removed from the database"
    $ object [identifier uid, "sessions" .= n]
