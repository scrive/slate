module API.Logging (
    logUserCompanyIPAndApiVersion
  , addAPIUserToContext
  ) where

import Data.Aeson
import Log

import API.APIVersion
import Kontra
import Log.Identifier
import OAuth.Util
import User.Data.User

logUserCompanyIPAndApiVersion :: Kontrakcja m => APIVersion -> m a -> m a
logUserCompanyIPAndApiVersion apiversion acc = do
  userandcompanyids <- (get ctxmaybeapiuser <$> getContext) >>= \case
    Nothing -> return []
    Just user -> do
      return
        [ identifier $ userid user
        , identifier $ usergroupid user
        ]
  ctx <- getContext
  let apiversionandip = [identifier apiversion, "ip" .= show (get ctxipnumber ctx)]
  localData (userandcompanyids ++ apiversionandip) $ do
    logInfo_ "API call"
    acc

-- Stick the user, which accesses API into the context
addAPIUserToContext :: Kontrakcja m => m ()
addAPIUserToContext = getMaybeAPIUserWithAnyPrivileges >>= modifyContext . set ctxmaybeapiuser
