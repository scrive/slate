module Company.Migrations where

import DB
import Company.Tables

removeServiceIDFromCompanies :: MonadDB m => Migration m
removeServiceIDFromCompanies = Migration {
    mgrTable = tableCompanies
  , mgrFrom = 6
  , mgrDo = do
    -- check if service_id field is empty for all companies
    check <- getMany "SELECT DISTINCT service_id IS NULL FROM companies"
    case check of
      []     -> return () -- no records, ok
      [True] -> return () -- only nulls, ok
      _      -> error "Companies have rows with non-null service_id"
    kRunRaw "ALTER TABLE companies DROP CONSTRAINT fk_companies_services"
    kRunRaw "DROP INDEX idx_companies_service_id"
    kRunRaw "ALTER TABLE companies DROP COLUMN service_id"
}

addEmailBrandingToCompany :: MonadDB m => Migration m
addEmailBrandingToCompany =
  Migration {
    mgrTable = tableCompanies
  , mgrFrom = 1
  , mgrDo = do
      kRunRaw "ALTER TABLE companies ADD COLUMN bars_background TEXT NULL"
      kRunRaw "ALTER TABLE companies ADD COLUMN logo BYTEA NULL"
      return ()
  }

addTextColourToEmailBranding :: MonadDB m => Migration m
addTextColourToEmailBranding =
  Migration {
    mgrTable = tableCompanies
  , mgrFrom = 2
  , mgrDo = kRunRaw "ALTER TABLE companies ADD COLUMN bars_textcolour TEXT NULL"
  }

addIdSerialOnCompanies :: MonadDB m => Migration m
addIdSerialOnCompanies =
  Migration {
    mgrTable = tableCompanies
  , mgrFrom = 3
  , mgrDo = do
      kRunRaw $ "CREATE SEQUENCE companies_id_seq"
      kRunRaw $ "SELECT setval('companies_id_seq',(SELECT COALESCE(max(id)+1,1000) FROM companies))"
      kRunRaw $ "ALTER TABLE companies ALTER id SET DEFAULT nextval('companies_id_seq')"
  }

addEmailDomainOnCompanies :: MonadDB m => Migration m
addEmailDomainOnCompanies =
  Migration {
    mgrTable = tableCompanies
  , mgrFrom = 4
  , mgrDo = kRunRaw $ "ALTER TABLE companies ADD COLUMN email_domain TEXT NULL"
  }

addDefaultEmptyStringsToSomeColumnsInCompaniesTable :: MonadDB m => Migration m
addDefaultEmptyStringsToSomeColumnsInCompaniesTable =
  Migration {
    mgrTable = tableCompanies
  , mgrFrom = 5
  , mgrDo = kRunRaw $ "ALTER TABLE companies"
    ++ " ALTER name SET DEFAULT '',"
    ++ " ALTER number SET DEFAULT '',"
    ++ " ALTER address SET DEFAULT '',"
    ++ " ALTER zip SET DEFAULT '',"
    ++ " ALTER city SET DEFAULT '',"
    ++ " ALTER country SET DEFAULT ''"
  }
