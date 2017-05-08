module Chargeable.Migrations where

import Database.PostgreSQL.PQTypes.Checks

import Chargeable.Tables
import DB
import KontraPrelude

createChargeableItemsTable :: MonadDB m => Migration m
createChargeableItemsTable = Migration {
  mgrTable = tableChargeableItems
, mgrFrom = 0
, mgrDo = createTable True tblTable {
    tblName = "chargeable_items"
  , tblVersion = 1
  , tblColumns = [
      tblColumn { colName = "id", colType = BigSerialT, colNullable = False }
    , tblColumn { colName = "time", colType = TimestampWithZoneT, colNullable = False }
    , tblColumn { colName = "company_id", colType = BigIntT, colNullable = False }
    , tblColumn { colName = "type", colType = SmallIntT, colNullable = False }
    , tblColumn { colName = "user_id", colType = BigIntT, colNullable = False }
    , tblColumn { colName = "document_id", colType = BigIntT, colNullable = False }
    , tblColumn { colName = "quantity", colType = IntegerT, colNullable = False }
    ]
  , tblPrimaryKey = pkOnColumn "id"
  , tblForeignKeys = [
      fkOnColumn "user_id" "users" "id"
    , fkOnColumn "company_id" "companies" "id"
    , fkOnColumn "document_id" "documents" "id"
    ]
    , tblIndexes = [
      indexOnColumn "user_id"
    , indexOnColumn "company_id"
    , indexOnColumn "document_id"
    ]
  }
}

createIndexOnTimeField :: MonadDB m => Migration m
createIndexOnTimeField = Migration {
    mgrTable = tableChargeableItems
  , mgrFrom = 1
  , mgrDo = do
      let tname = tblName tableChargeableItems
      runQuery_ . sqlCreateIndex tname $ (indexOnColumn "\"time\"")
  }
