module Stats.Migrations where

import DB
import Doc.DocStateData
import Stats.Tables

removeDocEventsThatReferenceNotActivatedUsers :: MonadDB m => Migration m
removeDocEventsThatReferenceNotActivatedUsers = Migration {
    mgrTable = tableDocStatEvents
  , mgrFrom = 3
  , mgrDo = kRunRaw "DELETE FROM doc_stat_events WHERE EXISTS (SELECT 1 FROM users WHERE deleted = FALSE AND user_id = id AND has_accepted_terms_of_service IS NULL)"
  }

removeUserRefuseSaveAfterSignEvent :: MonadDB m => Migration m
removeUserRefuseSaveAfterSignEvent = Migration {
    mgrTable = tableUserStatEvents
  , mgrFrom = 2
  , mgrDo = do
    kRunRaw $ "DELETE FROM user_stat_events WHERE quantity = 3"
    kRunRaw $ "UPDATE user_stat_events SET quantity = quantity - 1 WHERE quantity > 3"
  }

addServiceAndCompanyToStats :: MonadDB m => Migration m
addServiceAndCompanyToStats =
  Migration {
    mgrTable = tableDocStatEvents
  , mgrFrom = 1
  , mgrDo = do
      kRunRaw "ALTER TABLE doc_stat_events DROP CONSTRAINT pk_doc_stat_events"
      kRunRaw "ALTER TABLE doc_stat_events ADD CONSTRAINT pk_doc_stat_events PRIMARY KEY (quantity, document_id)"
      kRunRaw "ALTER TABLE doc_stat_events ADD COLUMN service_id    TEXT       NULL"
      kRunRaw "ALTER TABLE doc_stat_events ADD COLUMN company_id    BIGINT     NULL"
      kRunRaw "ALTER TABLE doc_stat_events ADD COLUMN document_type TEXT       NULL"
      _ <- kRun $ SQL "UPDATE doc_stat_events SET service_id = NULL, company_id = NULL, document_type = ? " [toSql $ show $ Signable Contract]
      kRunRaw "ALTER TABLE doc_stat_events ALTER COLUMN document_type SET   NOT NULL"
      kRunRaw $ "ALTER TABLE doc_stat_events"
           ++ " ADD CONSTRAINT fk_doc_stat_events_company FOREIGN KEY(company_id)"
           ++ " REFERENCES companies(id) ON UPDATE RESTRICT ON DELETE NO ACTION"
           ++ " DEFERRABLE INITIALLY IMMEDIATE"
      kRunRaw $ "ALTER TABLE doc_stat_events"
           ++ " ADD CONSTRAINT fk_doc_stat_events_service FOREIGN KEY(service_id)"
           ++ " REFERENCES services(id) ON UPDATE RESTRICT ON DELETE NO ACTION"
           ++ " DEFERRABLE INITIALLY IMMEDIATE"
  }

makeUserStatsRepeatableByChangingPK :: MonadDB m => Migration m
makeUserStatsRepeatableByChangingPK =
  Migration {
    mgrTable = tableUserStatEvents
  , mgrFrom = 1
  , mgrDo = do
      kRunRaw "CREATE SEQUENCE user_stat_events_id_seq"
      kRunRaw $ "ALTER TABLE user_stat_events"
           ++ " ADD COLUMN id BIGINT NOT NULL DEFAULT nextval('user_stat_events_id_seq')"
      kRunRaw $ "ALTER TABLE user_stat_events"
           ++ " DROP CONSTRAINT pk_user_stat_events"
      kRunRaw $ "ALTER TABLE user_stat_events"
           ++ " ADD CONSTRAINT pk_user_stat_events PRIMARY KEY (id)"
      return ()
  }

addAPIStringDocStats :: MonadDB m => Migration m
addAPIStringDocStats =
  Migration {
      mgrTable = tableDocStatEvents
    , mgrFrom = 2
    , mgrDo = do
        kRunRaw $ "ALTER TABLE doc_stat_events "
          ++      "ADD COLUMN api_string TEXT NOT NULL DEFAULT 'unknown'" 
        return ()
    }