module FeatureFlags.Tables (
  tableFeatureFlags
) where

import DB

tableFeatureFlags :: Table
tableFeatureFlags = tblTable {
    tblName = "feature_flags"
  , tblVersion = 5
  , tblColumns = [
      tblColumn { colName = "company_id", colType = BigSerialT, colNullable = False }
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
    , tblColumn { colName = "can_use_no_authentication_to_sign", colType = BoolT, colNullable = False, colDefault = Just "true" }
    , tblColumn { colName = "can_use_sms_pin_authentication_to_view", colType = BoolT, colNullable = False, colDefault = Just "true" }
    , tblColumn { colName = "can_use_dk_authentication_to_sign", colType = BoolT, colNullable = False, colDefault = Just "true" }
    , tblColumn { colName = "user_group_id", colType = BigIntT, colNullable = True }
    ]
  , tblPrimaryKey = pkOnColumn "company_id"
  , tblForeignKeys = [
      (fkOnColumn "company_id" "companies" "id") { fkOnDelete = ForeignKeyCascade }
    , (fkOnColumn "user_group_id" "user_groups" "id") { fkOnDelete = ForeignKeySetNull }
    ]
  , tblIndexes = [
      indexOnColumn "user_group_id"
    ]
  }
