module Amazon.Tables where

import DB

tableAmazonUploadConsumers :: Table
tableAmazonUploadConsumers = tblTable {
    tblName = "amazon_upload_consumers"
  , tblVersion = 1
  , tblColumns = [
      tblColumn { colName = "id", colType = BigSerialT, colNullable = False }
    , tblColumn { colName = "name", colType = TextT, colNullable = False }
    , tblColumn { colName = "last_activity", colType = TimestampWithZoneT, colNullable = False }
    ]
    , tblPrimaryKey = pkOnColumn "id"
  }

tableAmazonUploadJobs :: Table
tableAmazonUploadJobs = tblTable {
    tblName = "amazon_upload_jobs"
  , tblVersion = 1
  , tblColumns = [
      tblColumn { colName = "id", colType = BigIntT, colNullable = False }
    , tblColumn { colName = "run_at", colType = TimestampWithZoneT, colNullable = False }
    , tblColumn { colName = "finished_at", colType = TimestampWithZoneT }
    , tblColumn { colName = "reserved_by", colType = BigIntT }
    , tblColumn { colName = "attempts", colType = IntegerT, colNullable = False }
    ]
  , tblPrimaryKey = pkOnColumn "id"
  , tblForeignKeys = [
      (fkOnColumn "id" "files" "id") { fkOnDelete = ForeignKeyCascade }
    , (fkOnColumn "reserved_by" "amazon_upload_consumers" "id") {
        fkOnDelete = ForeignKeySetNull
      }
    ]
  }

tableAmazonURLFixConsumers :: Table
tableAmazonURLFixConsumers = tblTable {
    tblName = "amazon_url_fix_consumers"
  , tblVersion = 1
  , tblColumns = [
      tblColumn { colName = "id", colType = BigSerialT, colNullable = False }
    , tblColumn { colName = "name", colType = TextT, colNullable = False }
    , tblColumn { colName = "last_activity", colType = TimestampWithZoneT, colNullable = False }
    ]
    , tblPrimaryKey = pkOnColumn "id"
  }

tableAmazonURLFixJobs :: Table
tableAmazonURLFixJobs = tblTable {
    tblName = "amazon_url_fix_jobs"
  , tblVersion = 1
  , tblColumns = [
      tblColumn { colName = "id", colType = BigIntT, colNullable = False }
    , tblColumn { colName = "run_at", colType = TimestampWithZoneT, colNullable = False }
    , tblColumn { colName = "finished_at", colType = TimestampWithZoneT }
    , tblColumn { colName = "reserved_by", colType = BigIntT }
    , tblColumn { colName = "attempts", colType = IntegerT, colNullable = False }
    ]
  , tblPrimaryKey = pkOnColumn "id"
  , tblForeignKeys = [
      (fkOnColumn "id" "files" "id") { fkOnDelete = ForeignKeyCascade }
    , (fkOnColumn "reserved_by" "amazon_url_fix_consumers" "id") {
        fkOnDelete = ForeignKeySetNull
      }
    ]
  }
