{-# LANGUAGE StrictData #-}
module Flow.Tables where

import Database.PostgreSQL.PQTypes.Checks
import Database.PostgreSQL.PQTypes.Class
import Database.PostgreSQL.PQTypes.Model

flowTables :: [Table]
flowTables =
  [ tableFlowTemplates
  , tableFlowInstances
  , tableFlowInstancesKVStore
  , tableFlowInstanceSignatories
  , tableFlowInstanceAccessTokens
  , tableFlowInstanceSessions
  , tableFlowEvents
  , tableFlowAggregatorEvents
  ]

flowMigrations :: MonadDB m => [Migration m]
flowMigrations =
  [ createTableFlowTemplates
  , createTableFlowInstances
  , createTableFlowInstancesKVStore
  , createTableFlowInstanceSignatories
  , createTableFlowInstanceAccessTokens
  , createTableFlowInstanceSessions
  , createTableFlowEvents
  , createTableFlowAggregatorEvents
  ]

tableFlowTemplates :: Table
tableFlowTemplates = tblTable
  { tblName        = "flow_templates"
  , tblVersion     = 1
  , tblColumns     =
    [ tblColumn { colName     = "id"
                , colType     = UuidT
                , colNullable = False
                , colDefault  = Just "gen_random_uuid()"
                }
    , tblColumn { colName = "name", colType = TextT, colNullable = False }
    , tblColumn { colName = "process", colType = TextT, colNullable = False }
    , tblColumn { colName = "user_id", colType = BigIntT, colNullable = False }
    , tblColumn { colName = "folder_id", colType = BigIntT, colNullable = False }
    , tblColumn { colName = "created", colType = TimestampWithZoneT, colNullable = False }
    , tblColumn { colName = "committed", colType = TimestampWithZoneT }
    , tblColumn { colName = "deleted", colType = TimestampWithZoneT }
    ]
  , tblPrimaryKey  = pkOnColumn "id"
  , tblIndexes     = [indexOnColumn "user_id", indexOnColumn "folder_id"]
  , tblForeignKeys = [
    -- Do not allow to delete users or user groups that still contain templates.
                       fkOnColumn "user_id"   "users"   "id"
                     , fkOnColumn "folder_id" "folders" "id"
                     ]
  }

createTableFlowTemplates :: MonadDB m => Migration m
createTableFlowTemplates = Migration
  { mgrTableName = tblName tableFlowTemplates
  , mgrFrom      = 0
  , mgrAction    = StandardMigration $ createTable True tableFlowTemplates
  }

tableFlowInstances :: Table
tableFlowInstances = tblTable
  { tblName        = "flow_instances"
  , tblVersion     = 1
  , tblColumns     =
    [ tblColumn { colName     = "id"
                , colType     = UuidT
                , colNullable = False
                , colDefault  = Just "gen_random_uuid()"
                }
    , tblColumn { colName = "template_id", colType = UuidT, colNullable = False }
    , tblColumn { colName = "current_state", colType = TextT, colNullable = False }
    , tblColumn { colName = "created", colType = TimestampWithZoneT, colNullable = False }
    ]
  , tblPrimaryKey  = pkOnColumn "id"
  , tblIndexes     = [indexOnColumn "template_id"]
  , tblForeignKeys = [fkOnColumn "template_id" "flow_templates" "id"]
  }

createTableFlowInstances :: MonadDB m => Migration m
createTableFlowInstances = Migration
  { mgrTableName = tblName tableFlowInstances
  , mgrFrom      = 0
  , mgrAction    = StandardMigration $ createTable True tableFlowInstances
  }

tableFlowInstancesKVStore :: Table
tableFlowInstancesKVStore = tblTable
  { tblName        = "flow_instance_key_value_store"
  , tblVersion     = 1
  , tblColumns     =
    [ tblColumn { colName = "instance_id", colType = UuidT, colNullable = False }
    , tblColumn { colName = "key", colType = TextT, colNullable = False }
    -- TODO: Column `type` should be an enum, see the check below for allowed values.
    , tblColumn { colName = "type", colType = TextT, colNullable = False }
    , tblColumn { colName = "string", colType = TextT, colNullable = True }
    , tblColumn { colName = "document_id", colType = BigIntT, colNullable = True }
    , tblColumn { colName = "user_id", colType = BigIntT, colNullable = True }
    ]
  , tblPrimaryKey  = pkOnColumns ["instance_id", "key"]
  , tblIndexes     =
                      -- Documents cannot be associated with multiple instances.
                     [ uniqueIndexOnColumn "document_id"
                      -- Users associated with an instance cannot be used for multiple keys.
                     , uniqueIndexOnColumns ["instance_id", "user_id"]
                     ]
  , tblForeignKeys =
    [ (fkOnColumn "instance_id" "flow_instances" "id") { fkOnDelete = ForeignKeyCascade }
    , fkOnColumn "document_id" "documents" "id"
    , fkOnColumn "user_id"     "users"     "id"
    ]
  , tblChecks      =
    [ tblCheck
        { chkName      = "check_value"
        , chkCondition =
          "type = 'document'::text AND document_id IS NOT NULL OR \
        \type = 'user'::text AND user_id IS NOT NULL OR \
        \type = 'email'::text AND string IS NOT NULL OR \
        \type = 'phone_number'::text AND string IS NOT NULL OR \
        \type = 'message'::text AND string IS NOT NULL"
        }
    ]
  }

createTableFlowInstancesKVStore :: MonadDB m => Migration m
createTableFlowInstancesKVStore = Migration
  { mgrTableName = tblName tableFlowInstancesKVStore
  , mgrFrom      = 0
  , mgrAction    = StandardMigration $ createTable True tableFlowInstancesKVStore
  }

tableFlowInstanceSignatories :: Table
tableFlowInstanceSignatories = tblTable
  { tblName        = "flow_instance_signatories"
  , tblVersion     = 1
  , tblColumns     =
    [ tblColumn { colName = "signatory_id", colType = BigIntT, colNullable = False }
    , tblColumn { colName = "instance_id", colType = UuidT, colNullable = False }
    , tblColumn { colName = "key", colType = TextT, colNullable = False }
    ]
  , tblPrimaryKey  = pkOnColumn "signatory_id"
  , tblIndexes     = [indexOnColumns ["instance_id", "key"]]
  , tblForeignKeys = [ (fkOnColumns ["instance_id", "key"]
                                    "flow_instance_key_value_store"
                                    ["instance_id", "key"]
                       )
                       { fkOnDelete = ForeignKeyCascade
                       }
                     , fkOnColumn "signatory_id" "signatory_links" "id"
                     ]
  }

createTableFlowInstanceSignatories :: MonadDB m => Migration m
createTableFlowInstanceSignatories = Migration
  { mgrTableName = tblName tableFlowInstanceSignatories
  , mgrFrom      = 0
  , mgrAction    = StandardMigration $ createTable True tableFlowInstanceSignatories
  }

tableFlowInstanceAccessTokens :: Table
tableFlowInstanceAccessTokens = tblTable
  { tblName        = "flow_instance_access_tokens"
  , tblVersion     = 1
  , tblColumns = [ tblColumn { colName     = "id"
                             , colType     = UuidT
                             , colNullable = False
                             , colDefault  = Just "gen_random_uuid()"
                             }
    -- TODO: add expiration time?
                 , tblColumn { colName = "hash", colType = BigIntT, colNullable = False }
                 , tblColumn { colName     = "instance_id"
                             , colType     = UuidT
                             , colNullable = False
                             }
                 , tblColumn { colName = "key", colType = TextT, colNullable = False }
                 ]
  , tblPrimaryKey  = pkOnColumn "id"
  , tblIndexes     = [indexOnColumns ["instance_id", "key"]]
  , tblForeignKeys = [ (fkOnColumns ["instance_id", "key"]
                                    "flow_instance_key_value_store"
                                    ["instance_id", "key"]
                       )
                         { fkOnDelete = ForeignKeyCascade
                         }
                     ]
  }

createTableFlowInstanceAccessTokens :: MonadDB m => Migration m
createTableFlowInstanceAccessTokens = Migration
  { mgrTableName = tblName tableFlowInstanceAccessTokens
  , mgrFrom      = 0
  , mgrAction    = StandardMigration $ createTable True tableFlowInstanceAccessTokens
  }

-- | This table links Kontrakcja sessions to "Flow instance users", creating
-- "instance sessions". Instance sessions are created only for Flow users who
-- have authenticated with a valid invitation link.
tableFlowInstanceSessions :: Table
tableFlowInstanceSessions = tblTable
  { tblName        = "flow_instance_sessions"
  , tblVersion     = 1
  , tblColumns     =
    [ tblColumn { colName = "session_id", colType = BigIntT, colNullable = False }
    , tblColumn { colName = "instance_id", colType = UuidT, colNullable = False }
    , tblColumn { colName = "key", colType = TextT, colNullable = False }
    ]
  , tblPrimaryKey  = pkOnColumn "session_id"
  , tblIndexes     = [indexOnColumn "session_id"]
  , tblForeignKeys =
    [ (fkOnColumns ["instance_id", "key"]
                   "flow_instance_key_value_store"
                   ["instance_id", "key"]
      ) { fkOnDelete = ForeignKeyCascade
        }
    , (fkOnColumn "session_id" "sessions" "id") { fkOnDelete = ForeignKeyCascade }
    ]
  }

createTableFlowInstanceSessions :: MonadDB m => Migration m
createTableFlowInstanceSessions = Migration
  { mgrTableName = tblName tableFlowInstanceSessions
  , mgrFrom      = 0
  , mgrAction    = StandardMigration $ createTable True tableFlowInstanceSessions
  }

tableFlowEvents :: Table
tableFlowEvents = tblTable
  { tblName        = "flow_events"
  , tblVersion     = 1
  , tblColumns     =
    [ tblColumn { colName     = "id"
                , colType     = UuidT
                , colNullable = False
                , colDefault  = Just "gen_random_uuid()"
                }
    , tblColumn { colName = "instance_id", colType = UuidT, colNullable = False }
    , tblColumn { colName = "user_name", colType = TextT, colNullable = False }
    , tblColumn { colName = "document_name", colType = TextT, colNullable = False }
    , tblColumn { colName = "user_action", colType = TextT, colNullable = False }
    , tblColumn { colName = "created", colType = TimestampWithZoneT, colNullable = False }
    ]
  , tblPrimaryKey  = pkOnColumn "id"
  , tblIndexes     = [indexOnColumn "instance_id"]
  , tblForeignKeys =
    [(fkOnColumn "instance_id" "flow_instances" "id") { fkOnDelete = ForeignKeyCascade }]
  }

createTableFlowEvents :: MonadDB m => Migration m
createTableFlowEvents = Migration
  { mgrTableName = tblName tableFlowEvents
  , mgrFrom      = 0
  , mgrAction    = StandardMigration $ createTable True tableFlowEvents
  }

tableFlowAggregatorEvents :: Table
tableFlowAggregatorEvents = tblTable
  { tblName        = "flow_aggregator_events"
  , tblVersion     = 1
  , tblColumns     = [tblColumn { colName = "id", colType = UuidT, colNullable = False }]
  , tblPrimaryKey  = pkOnColumn "id"
  , tblForeignKeys =
    [(fkOnColumn "id" "flow_events" "id") { fkOnDelete = ForeignKeyCascade }]
  }

createTableFlowAggregatorEvents :: MonadDB m => Migration m
createTableFlowAggregatorEvents = Migration
  { mgrTableName = tblName tableFlowAggregatorEvents
  , mgrFrom      = 0
  , mgrAction    = StandardMigration $ createTable True tableFlowAggregatorEvents
  }
