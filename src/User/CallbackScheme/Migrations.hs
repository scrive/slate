module User.CallbackScheme.Migrations where

import DB
import User.CallbackScheme.Tables

removeDuplicateIndexFromUsersCallbackScheme :: MonadDB m => Migration m
removeDuplicateIndexFromUsersCallbackScheme = Migration {
  mgrTable = tableUsersCallbackScheme
, mgrFrom = 1
, mgrDo = do
  let Table{..} = tableUsersCallbackScheme
  kRun_ . sqlDropIndex tblName $ indexOnColumn "user_id"
}
