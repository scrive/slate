module FeatureFlags.Migrations (
  createFeatureFlags
, featureFlagsAddNOAuthToSign
, featureFlagsAddSMSPinAuthToView
, featureFlagsAddDKAuthToSign
, featureFlagsAddUserGroupID
, featureFlagsDropCompanyID
) where

import Control.Monad.Catch
import Database.PostgreSQL.PQTypes.Checks

import DB
import FeatureFlags.Tables

createFeatureFlags :: MonadDB m => Migration m
createFeatureFlags = Migration {
    mgrTableName = tblName tableFeatureFlags
  , mgrFrom = 0
  , mgrAction = StandardMigration $ do
      createTable True tblTable {
        tblName = "feature_flags"
        , tblVersion = 1
        , tblColumns =
          [ tblColumn { colName = "company_id", colType = BigSerialT, colNullable = False }
          , tblColumn { colName = "can_use_templates", colType = BoolT, colNullable = False, colDefault = Just "true" }
          , tblColumn { colName = "can_use_branding", colType = BoolT, colNullable = False, colDefault = Just "true" }
          , tblColumn { colName = "can_use_author_attachments", colType = BoolT, colNullable = False, colDefault = Just "true" }
          , tblColumn { colName = "can_use_signatory_attachments", colType = BoolT, colNullable = False, colDefault = Just "true" }
          , tblColumn { colName = "can_use_mass_sendout", colType = BoolT, colNullable = False, colDefault = Just "true" }

          , tblColumn { colName = "can_use_sms_invitations", colType = BoolT, colNullable = False, colDefault = Just "true" }
          , tblColumn { colName = "can_use_sms_confirmations", colType = BoolT, colNullable = False, colDefault = Just "true" }

          , tblColumn { colName = "can_use_dk_authentication_to_view", colType = BoolT, colNullable = False, colDefault = Just "true" }
          , tblColumn { colName = "can_use_no_authentication_to_view", colType = BoolT, colNullable = False, colDefault = Just "true" }
          , tblColumn { colName = "can_use_se_authentication_to_view", colType = BoolT, colNullable = False, colDefault = Just "true" }
          , tblColumn { colName = "can_use_se_authentication_to_sign", colType = BoolT, colNullable = False, colDefault = Just "true" }
          , tblColumn { colName = "can_use_sms_pin_authentication_to_sign", colType = BoolT, colNullable = False, colDefault = Just "true" }
          ]
        , tblPrimaryKey = pkOnColumn "company_id"
        , tblForeignKeys = [
            (fkOnColumn "company_id" "companies" "id") { fkOnDelete = ForeignKeyCascade }
          ]
        }
      runQuery_ . sqlInsertSelect "feature_flags" "companies c" $ do
        sqlSetCmd "company_id" "c.id"
  }

featureFlagsAddNOAuthToSign :: (MonadThrow m, MonadDB m) => Migration m
featureFlagsAddNOAuthToSign = Migration {
  mgrTableName = tblName tableFeatureFlags
, mgrFrom = 1
, mgrAction = StandardMigration $ do
    runQuery_ $ sqlAlterTable (tblName tableFeatureFlags)  [ sqlAddColumn $
        tblColumn { colName = "can_use_no_authentication_to_sign", colType = BoolT, colNullable = False, colDefault = Just "true" }
      ]
}

featureFlagsAddSMSPinAuthToView :: (MonadThrow m, MonadDB m) => Migration m
featureFlagsAddSMSPinAuthToView = Migration {
  mgrTableName = tblName tableFeatureFlags
, mgrFrom = 2
, mgrAction = StandardMigration $ do
    runQuery_ $ sqlAlterTable (tblName tableFeatureFlags)  [ sqlAddColumn $
        tblColumn { colName = "can_use_sms_pin_authentication_to_view", colType = BoolT, colNullable = False, colDefault = Just "true" }
      ]
}

featureFlagsAddDKAuthToSign :: (MonadThrow m, MonadDB m) => Migration m
featureFlagsAddDKAuthToSign = Migration {
  mgrTableName = tblName tableFeatureFlags
, mgrFrom = 3
, mgrAction = StandardMigration $ do
    runQuery_ $ sqlAlterTable (tblName tableFeatureFlags)  [ sqlAddColumn $
        tblColumn { colName = "can_use_dk_authentication_to_sign", colType = BoolT, colNullable = False, colDefault = Just "true" }
      ]
}

featureFlagsAddUserGroupID :: (MonadThrow m, MonadDB m) => Migration m
featureFlagsAddUserGroupID = Migration {
  mgrTableName = tblName tableFeatureFlags
, mgrFrom = 4
, mgrAction = StandardMigration $ do
    let tname = tblName tableFeatureFlags
    runQuery_ $ sqlAlterTable tname
      [
        sqlAddColumn $ tblColumn { colName = "user_group_id", colType = BigIntT, colNullable = True }
      ,  sqlAddFK tname $ (fkOnColumn "user_group_id" "user_groups" "id") { fkOnDelete = ForeignKeySetNull }
      ]
    runQuery_ . sqlCreateIndex tname $ indexOnColumn "user_group_id"
}


featureFlagsDropCompanyID :: MonadDB m => Migration m
featureFlagsDropCompanyID = Migration {
    mgrTableName = tblName tableFeatureFlags
  , mgrFrom = 5
  , mgrAction = StandardMigration $ do
      let tname = tblName tableFeatureFlags
      runQuery_ $ sqlAlterTable tname [
          sqlAlterColumn "user_group_id" "SET NOT NULL"
        , sqlDropFK tname $ (fkOnColumn "company_id" "companies" "id")
        , sqlDropFK tname $ (fkOnColumn "user_group_id" "user_groups" "id")
        , sqlAddFK  tname $ (fkOnColumn "user_group_id" "user_groups" "id") { fkOnDelete = ForeignKeyCascade }
        , sqlDropPK tname
        , sqlAddPK tname (fromJust $ pkOnColumn "user_group_id")
        , sqlDropColumn "company_id"
        ]
      runQuery_ $ sqlDropIndex tname $ (indexOnColumn "user_group_id")

  }
