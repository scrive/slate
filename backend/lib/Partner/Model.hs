module Partner.Model (
  PartnerID
, Partner(..)
, GetPartners(..)
, IsUserPartnerAdmin(..)
, GetPartnerByID(..)
, AddNewPartner(..)
, unsafePartnerID
, unPartnerID
) where

import Control.Monad.Catch
import Log

import DB
import Partner.Partner
import User.UserID
import UserGroup.Data

fetchPartner :: (PartnerID, String, Bool, Maybe UserGroupID) -> Partner
fetchPartner (pid, pname, pdef, mugid) =
  Partner
    { ptID = pid
    , ptName = pname
    , ptDefaultPartner = pdef
    , ptUserGroupID = mugid
    }

partnerSelector :: [SQL]
partnerSelector =
  [ "id"
  , "name"
  , "default_partner"
  , "user_group_id"
  ]

data GetPartners = GetPartners
instance (MonadDB m, MonadLog m) => DBQuery m GetPartners [Partner] where
  query (GetPartners) = do
    runQuery_ . sqlSelect "partners" $ do
      mapM_ sqlResult $ partnerSelector
      sqlOrderBy "id"
    fetchMany fetchPartner

data IsUserPartnerAdmin = IsUserPartnerAdmin UserID PartnerID
instance (MonadDB m, MonadThrow m, MonadLog m) => DBQuery m IsUserPartnerAdmin Bool where
  query (IsUserPartnerAdmin uid pid) = do
    runQuery01 . sqlSelect "partner_admins" $ do
      sqlWhereEq "user_id" uid
      sqlWhereEq "partner_id" pid
      sqlResult "TRUE"

data GetPartnerByID = GetPartnerByID PartnerID
instance (MonadDB m, MonadThrow m, MonadLog m) => DBQuery m GetPartnerByID Partner where
  query (GetPartnerByID pid) = do
    runQuery_ . sqlSelect "partners" $ do
      mapM_ sqlResult $ partnerSelector
      sqlWhereEq "id" pid
    fetchOne fetchPartner

-- to convert to UserGroup here, we would need to create some "empty" company and user_group
-- since this is never called except for tests, lets assume that this will not happen during
-- company to user_groups migration.
data AddNewPartner = AddNewPartner String
instance (MonadDB m, MonadThrow m, MonadLog m) => DBUpdate m AddNewPartner PartnerID where
  update (AddNewPartner name) = do
    runQuery_ . sqlInsert "partners" $ do
      sqlSet "name" name
      sqlSet "default_partner" False -- @note one can't create a new default partner
      sqlResult "id"
    newPartnerID <- fetchOne runIdentity
    return newPartnerID
