{-# LANGUAGE ExtendedDefaultRules #-}
module User.Migrations where

import DB
import DB.SQL2
import User.Tables
import User.Model (UserID)
import Company.Model (CompanyID)
import Control.Monad
default (SQL)

addUserCustomFooter :: MonadDB m => Migration m
addUserCustomFooter =
  Migration {
    mgrTable = tableUsers
  , mgrFrom = 3
  , mgrDo = do
      kRunRaw "ALTER TABLE users ADD COLUMN customfooter TEXT"
      _ <- kRun $ SQL "UPDATE users SET customfooter = ?" [SqlNull]
      return ()
  }

removeSystemServer :: MonadDB m => Migration m
removeSystemServer =
  Migration {
    mgrTable = tableUsers
  , mgrFrom = 2
  , mgrDo = do
      kRunRaw "ALTER TABLE users DROP COLUMN system_server CASCADE"
  }

addRegionToUserSettings :: MonadDB m => Migration m
addRegionToUserSettings =
  Migration {
    mgrTable = tableUsers
  , mgrFrom = 1
  , mgrDo = do
      kRunRaw "ALTER TABLE users ADD COLUMN region SMALLINT"
      _ <- kRun $ SQL "UPDATE users SET region = ?" [defaultRegion]
      kRunRaw "ALTER TABLE users ALTER COLUMN region SET NOT NULL"
  }
  where defaultRegion = toSql (1 :: Integer)

addIdSerialOnUsers :: MonadDB m => Migration m
addIdSerialOnUsers =
  Migration {
    mgrTable = tableUsers
  , mgrFrom = 4
  , mgrDo = do
      _ <- kRunRaw $ "CREATE SEQUENCE users_id_seq"
      _ <- kRunRaw $ "SELECT setval('users_id_seq',(SELECT COALESCE(max(id)+1,1000) FROM users))"
      _ <- kRunRaw $ "ALTER TABLE users ALTER id SET DEFAULT nextval('users_id_seq')"
      return ()
  }

addCompanyNameNumberOnUsers :: MonadDB m => Migration m
addCompanyNameNumberOnUsers =
  Migration {
    mgrTable = tableUsers
  , mgrFrom = 5
  , mgrDo = do
      _ <- kRunRaw $ "ALTER TABLE users ADD COLUMN company_name   TEXT NOT NULL DEFAULT ''"
      _ <- kRunRaw $ "ALTER TABLE users ADD COLUMN company_number TEXT NOT NULL DEFAULT ''"
      return ()
  }

addCheckLowercaseEmailsUsers :: MonadDB m => Migration m
addCheckLowercaseEmailsUsers =
  Migration {
    mgrTable = tableUsers
  , mgrFrom = 6
  , mgrDo = do
      _ <- kRunRaw $ "UPDATE users SET email = lower(email)"
      _ <- kRunRaw $ "ALTER TABLE users ADD CONSTRAINT users_email_lowercase_chk CHECK (email = lower(email))"
      return ()
  }

removePreferedDesignMode :: MonadDB m => Migration m
removePreferedDesignMode =
  Migration {
    mgrTable = tableUsers
  , mgrFrom = 7
  , mgrDo = do
      _ <- kRunRaw $ "ALTER TABLE users DROP COLUMN preferred_design_mode"
      return ()
  }

addIsFree :: MonadDB m => Migration m
addIsFree =
  Migration {
      mgrTable = tableUsers
    , mgrFrom = 8
    , mgrDo = do
      _ <- kRunRaw $ "ALTER TABLE users ADD COLUMN is_free BOOL NOT NULL DEFAULT FALSE"
      return ()
    }

removeServiceIDFromUsers :: MonadDB m => Migration m
removeServiceIDFromUsers = Migration {
    mgrTable = tableUsers
  , mgrFrom = 9
  , mgrDo = do
    -- check if service_id field is empty for all users
    check <- getMany "SELECT DISTINCT service_id IS NULL FROM users"
    case check of
      []     -> return () -- no records, ok
      [True] -> return () -- only nulls, ok
      _      -> error "Users have rows with non-null service_id"
    kRunRaw "ALTER TABLE users DROP CONSTRAINT fk_users_services"
    kRunRaw "DROP INDEX idx_users_service_id"
    kRunRaw "ALTER TABLE users DROP COLUMN service_id"
}

removeRegionFromUsers :: MonadDB m => Migration m
removeRegionFromUsers = Migration {
    mgrTable = tableUsers
  , mgrFrom = 10
  , mgrDo = kRunRaw "ALTER TABLE users DROP COLUMN region"
}

dropCustomFooterFromUsers :: MonadDB m => Migration m
dropCustomFooterFromUsers = Migration {
    mgrTable = tableUsers
  , mgrFrom = 11
  , mgrDo = kRunRaw "ALTER TABLE users DROP COLUMN customfooter"
}

addAssociatedDomainToUsers :: MonadDB m => Migration m
addAssociatedDomainToUsers = Migration {
    mgrTable = tableUsers
  , mgrFrom = 12
  , mgrDo = kRunRaw "ALTER TABLE users ADD COLUMN associated_domain TEXT NULL"

}

dropMobileFromUsers :: MonadDB m => Migration m
dropMobileFromUsers = Migration {
    mgrTable = tableUsers
  , mgrFrom = 13
  , mgrDo = kRunRaw "ALTER TABLE users DROP COLUMN mobile"

}
removeIsFree :: MonadDB m => Migration m
removeIsFree =
  Migration {
      mgrTable = tableUsers
    , mgrFrom = 14
    , mgrDo = do
      _ <- kRunRaw $ "ALTER TABLE users DROP COLUMN is_free"
      return ()
    }

allUsersMustHaveCompany :: MonadDB m => Migration m
allUsersMustHaveCompany =
  Migration {
      mgrTable = tableUsers
    , mgrFrom = 15
    , mgrDo = do
       kRun_ $ sqlSelect "users" $ do
                  sqlResult "id, company_name, company_number"
                  sqlWhere "company_id IS NULL"
       usersWithoutCompany <- kFold (\a u cn cnn -> (u,cn,cnn) : a) []
       forM_ usersWithoutCompany $ \(userid::UserID, companyname::String, companynumber::String) -> do
            _ <- kRun $ sqlInsert "companies" $ do
                            sqlSet "name" companyname
                            sqlSet "number" companynumber
                            sqlResult "id"
            (companyidx :: CompanyID) <- kFold (flip (:)) [] >>= exactlyOneObjectReturnedGuard

            kRun_ $ sqlInsert "company_uis" $ do
                sqlSet "company_id" companyidx

            kRun_ $ sqlUpdate "users" $ do
                sqlSet "company_id" companyidx
                sqlSet "is_company_admin" True
                sqlWhereEq "id" userid
       _ <- kRunRaw $ "ALTER TABLE users DROP COLUMN company_name"
       _ <- kRunRaw $ "ALTER TABLE users DROP COLUMN company_number"
       return ()
    }

migrateUsersDeletedTime :: MonadDB m => Migration m
migrateUsersDeletedTime =
  Migration {
      mgrTable = tableUsers
    , mgrFrom = 16
    , mgrDo = do
       _ <- kRunRaw $ "ALTER TABLE users"
                  <+> "ALTER deleted DROP NOT NULL,"
                  <+> "ALTER deleted DROP DEFAULT,"
                  <+> "ALTER deleted TYPE TIMESTAMPTZ USING (CASE WHEN deleted THEN now() ELSE NULL END)"
       return ()
    }
