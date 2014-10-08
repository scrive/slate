module DB.Checks (
    migrateDatabase
  , checkDatabase
  , createTable
  ) where

import Control.Applicative
import Control.Monad.Reader
import Control.Monad.Catch
import Data.Int
import Data.Maybe
import Data.Monoid
import Data.Monoid.Space
import Data.Monoid.Utils
import Database.PostgreSQL.PQTypes
import qualified Data.ByteString.Char8 as BS
import qualified Data.ByteString.UTF8 as BSU
import qualified Data.List as L
import qualified Data.Set as S

import DB.Model
import DB.SQL
import DB.Versions

newtype ValidationResult = ValidationResult [String] -- ^ list of error messages

instance Monoid ValidationResult where
  mempty = ValidationResult []
  mappend (ValidationResult a) (ValidationResult b) = ValidationResult (a ++ b)

-- | Runs all checks on a database
migrateDatabase :: (MonadDB m, MonadThrow m)
                => (String -> m ()) -> [Table] -> [Migration m] -> m ()
migrateDatabase logger tables migrations = do
  set <- setByteaOutput logger
  when set $ do
    commit
    error $ "Bytea_output was changed to 'hex'. Restart application so the change is visible."
  _ <- checkDBTimeZone logger
  checkNeededExtensions logger
  checkDBConsistency logger (tableVersions : tables) migrations
  checkDBStructure logger (tableVersions : tables)
  checkUnknownTables logger tables

  -- everything is OK, commit changes
  commit

checkDatabase :: (MonadDB m, MonadThrow m) => (String -> m ()) -> [Table] -> m ()
checkDatabase logger tables = do
  versions <- mapM checkTableVersion tables
  let tablesWithVersions = zip tables (map (fromMaybe 0) versions)

  let results = flip map tablesWithVersions $ \(t,v) ->
                if tblVersion t == v
                   then ValidationResult []
                   else if v==0
                        then ValidationResult ["Table '" ++ tblNameString t ++ "' must be created"]
                        else ValidationResult ["Table '" ++ tblNameString t ++ "' must be migrated " ++ show v ++ "->" ++ show (tblVersion t)]

  case mconcat results of
    ValidationResult [] -> return ()
    ValidationResult errmsgs -> do
      mapM_ logger errmsgs
      error "Failed"

  checkDBStructure logger (tableVersions : tables)
  return ()


-- | Return SQL fragment of current catalog within quotes
currentCatalog :: (MonadDB m, MonadThrow m) => m (RawSQL ())
currentCatalog = do
  runSQL_ "SELECT current_catalog::text"
  dbname <- fetchOne unSingle
  return $ unsafeSQL $ "\"" ++ dbname ++ "\""

checkNeededExtensions :: MonadDB m => (String -> m ()) -> m ()
checkNeededExtensions logger = do
  logger $ "Enabling needed extensions"
  runSQL_ $ "CREATE EXTENSION IF NOT EXISTS pgcrypto"
  return ()

-- |  Checks whether database returns timestamps in UTC
checkDBTimeZone :: (MonadDB m, MonadThrow m) => (String -> m ()) -> m Bool
checkDBTimeZone logger = do
  runSQL_ "SHOW timezone"
  timezone :: String <- fetchOne unSingle
  if timezone /= "UTC"
    then do
      dbname <- currentCatalog
      logger $ "Setting '" ++ sqlToString dbname ++ "' database to return timestamps in UTC"
      runQuery_ $ "ALTER DATABASE" <+> dbname <+> "SET TIMEZONE = 'UTC'"
      return True
    else return False

setByteaOutput :: (MonadDB m, MonadThrow m) => (String -> m ()) -> m Bool
setByteaOutput logger = do
  runSQL_ "SHOW bytea_output"
  bytea_output :: String <- fetchOne unSingle
  if bytea_output /= "hex"
    then do
      logger $ "Setting bytea_output to 'hex'..."
      dbname <- currentCatalog
      runQuery_ $ "ALTER DATABASE" <+> dbname <+> "SET bytea_output = 'hex'"
      return True
    else return False

checkUnknownTables :: MonadDB m => (String -> m ()) -> [Table] -> m ()
checkUnknownTables logger tables = do
  runQuery_ $ sqlSelect "information_schema.tables" $ do
    sqlResult "table_name::text"
    sqlWhere "table_name <> 'table_versions'"
    sqlWhere "table_type = 'BASE TABLE'"
    sqlWhere "table_schema NOT IN ('information_schema','pg_catalog')"
  desc <- fetchMany unSingle
  let absent = desc L.\\ map (BS.unpack . unRawSQL . tblName) tables
  when (not (null absent)) $
    mapM_ (\t -> logger $ "Unknown table '" ++ t) absent

createTable :: MonadDB m => Table -> m ()
createTable table@Table{..} = do
  forM_ createTableSQLs runQuery_

  case tblInitialData of
    Nothing -> return ()
    Just (Rows cols rows) -> forM_ rows $ \row -> runQuery_ $ rawSQL (smconcat [
        "INSERT INTO" <+> unRawSQL tblName
      , "(" <> mintercalate ", " cols <> ")"
      , "VALUES"
      , "(" <> mintercalate ", " colnums <> ")"
      ]) row
      where
        colnums = take (length cols) $ map (BS.pack . ('$':) . show) [1..]

  runQuery_ . sqlInsert "table_versions" $ do
    sqlSet "name" (tblNameString table)
    sqlSet "version" tblVersion
  where
    createTableSQLs :: [RawSQL ()]
    createTableSQLs = concat
      [ [sqlCreateTable tblName]
      , [sqlAlterTable tblName $ map sqlAddColumn tblColumns | not (null tblColumns)]
      , [sqlAlterTable tblName [sqlAddPK tblName pk] | Just pk <- return tblPrimaryKey ]
      , [sqlAlterTable tblName $ map sqlAddCheck tblChecks | not (null tblChecks)]
      , map (sqlCreateIndex tblName) tblIndexes
      , [sqlAlterTable tblName $ map (sqlAddFK tblName) tblForeignKeys | not (null tblForeignKeys)]
      ]

-- | Checks whether database is consistent (performs migrations if necessary)
checkDBStructure :: forall m. (MonadDB m, MonadThrow m)
                   => (String -> m ()) -> [Table]
                   -> m ()
checkDBStructure logger tables = do
  -- final checks for table structure, we do this both when creating stuff and when migrating
  result <- forM tables $ \table@Table{..} -> do
      result <- checkTableStructure table
      case result of
        ValidationResult [] -> return result
        ValidationResult errmsgs -> do
          return $ ValidationResult (("There are problems with table '" ++ tblNameString table ++ "'"):errmsgs)

  case mconcat result of
    ValidationResult [] -> return ()
    ValidationResult errmsgs -> do
      mapM_ logger errmsgs
      error "Failed"
  where
    checkTableStructure :: Table -> m ValidationResult
    checkTableStructure table@Table{..} = do
      -- get table description from pg_catalog as describeTable
      -- mechanism from HDBC doesn't give accurate results
      runQuery_ $ sqlSelect "pg_catalog.pg_attribute a" $ do
        sqlResult "a.attname::text"
        sqlResult "pg_catalog.format_type(a.atttypid, a.atttypmod)"
        sqlResult "NOT a.attnotnull"
        sqlResult . parenthesize . toSQLCommand $
          sqlSelect "pg_catalog.pg_attrdef d" $ do
            sqlResult "pg_catalog.pg_get_expr(d.adbin, d.adrelid)"
            sqlWhere "d.adrelid = a.attrelid"
            sqlWhere "d.adnum = a.attnum"
            sqlWhere "a.atthasdef"
        sqlWhere "a.attnum > 0"
        sqlWhere "NOT a.attisdropped"
        sqlWhereEqSql "a.attrelid" $ sqlGetTableID table
        sqlOrderBy "a.attnum"
      desc <- fetchMany fetchTableColumn
      -- get info about constraints from pg_catalog
      runQuery_ $ sqlGetPrimaryKey table
      pk <- join <$> fetchMaybe fetchPrimaryKey
      runQuery_ $ sqlGetChecks table
      checks <- fetchMany fetchTableCheck
      runQuery_ $ sqlGetIndexes table
      indexes <- fetchMany fetchTableIndex
      runQuery_ $ sqlGetForeignKeys table
      fkeys <- fetchMany fetchForeignKey
      return $ mconcat [
          checkColumns 1 tblColumns desc
        , checkPrimaryKey tblPrimaryKey pk
        , checkChecks tblChecks checks
        , checkIndexes tblIndexes indexes
        , checkForeignKeys tblForeignKeys fkeys
        ]
      where
        fetchTableColumn :: (String, ColumnType, Bool, Maybe String) -> TableColumn
        fetchTableColumn (name, ctype, nullable, mdefault) = TableColumn {
            colName = unsafeSQL name
          , colType = ctype
          , colNullable = nullable
          , colDefault = unsafeSQL `liftM` mdefault
          }

        checkColumns :: Int -> [TableColumn] -> [TableColumn] -> ValidationResult
        checkColumns _ [] [] = mempty
        checkColumns _ rest [] = ValidationResult [tableHasLess "columns" rest]
        checkColumns _ [] rest = ValidationResult [tableHasMore "columns" rest]
        checkColumns !n (d:defs) (c:cols) = mconcat [
            validateNames $ colName d == colName c
          -- bigserial == bigint + autoincrement and there is no
          -- distinction between them after table is created.
          , validateTypes $ colType d == colType c || (colType d == BigSerialT && colType c == BigIntT)
          -- there is a problem with default values determined by sequences as
          -- they're implicitely specified by db, so let's omit them in such case
          , validateDefaults $ colDefault d == colDefault c || (colDefault d == Nothing && ((BS.isPrefixOf "nextval('" . unRawSQL) `liftM` colDefault c) == Just True)
          , validateNullables $ colNullable d == colNullable c
          , checkColumns (n+1) defs cols
          ]
          where
            validateNames True = mempty
            validateNames False = ValidationResult [errorMsg ("no. " ++ show n) "names" (sqlToString . colName)]

            validateTypes True = mempty
            validateTypes False = ValidationResult [(errorMsg cname "types" (show . colType)) ++ " " ++ sql_hint ("TYPE" <+> columnTypeToSQL (colType d))]

            validateNullables True = mempty
            validateNullables False = ValidationResult [(errorMsg cname "nullables" (show . colNullable)) ++ " " ++ sql_hint ((if colNullable d then "DROP" else "SET") <+> "NOT NULL")]

            validateDefaults True = mempty
            validateDefaults False = ValidationResult [(errorMsg cname "defaults" (show . colDefault)) ++ " " ++ sql_hint set_default]
              where
                set_default = case colDefault d of
                  Just v  -> "SET DEFAULT" <+> v
                  Nothing -> "DROP DEFAULT"

            cname = sqlToString . colName $ d
            errorMsg ident attr f = "Column '" ++ ident ++ "' differs in " ++ attr ++ " (table: " ++ f c ++ ", definition: " ++ f d ++ ")."
            sql_hint sql = "(HINT: SQL for making the change is: ALTER TABLE " ++ tblNameString table ++ " ALTER COLUMN " ++ sqlToString (colName d) ++ " " ++ sqlToString sql ++ ")"

        checkPrimaryKey :: Maybe PrimaryKey -> Maybe (PrimaryKey, RawSQL ()) -> ValidationResult
        checkPrimaryKey mdef mpk = mconcat [
            checkEquality "PRIMARY KEY" def (map fst pk)
          , checkNames (const (pkName tblName)) pk
          ]
          where
            def = maybeToList mdef
            pk = maybeToList mpk

        checkChecks :: [TableCheck] -> [TableCheck] -> ValidationResult
        checkChecks defs checks = case checkEquality "CHECKs" defs checks of
          ValidationResult [] -> ValidationResult []
          ValidationResult errmsgs -> ValidationResult $ errmsgs ++ [" (HINT: If checks are equal modulo number of parentheses/whitespaces used in conditions, just copy and paste expected output into source code)"]

        checkIndexes :: [TableIndex] -> [(TableIndex, RawSQL ())] -> ValidationResult
        checkIndexes defs indexes = mconcat [
            checkEquality "INDEXes" defs (map fst indexes)
          , checkNames (indexName tblName) indexes
          ]

        checkForeignKeys :: [ForeignKey] -> [(ForeignKey, RawSQL ())] -> ValidationResult
        checkForeignKeys defs fkeys = mconcat [
            checkEquality "FOREIGN KEYs" defs (map fst fkeys)
          , checkNames (fkName tblName) fkeys
          ]

-- | Checks whether database is consistent (performs migrations if necessary)
checkDBConsistency :: forall m. (MonadDB m, MonadThrow m)
                   => (String -> m ()) -> [Table] -> [Migration m]
                   -> m ()
checkDBConsistency logger tables migrations = do

  -- check if migrations list has the following properties:
  -- - consecutive mgrFrom numbers
  -- - no duplicates
  -- - all mgrFrom are less than table version number of the table in the database (or the just created table)
  forM_ tables $ \table -> do
    let presentMigrationVersions = map mgrFrom $
                  filter (\m -> tblNameString (mgrTable m) == tblNameString table) migrations
        expectedMigrationVersions = reverse (take (length presentMigrationVersions) (reverse  [0 .. tblVersion table - 1]))
    when (presentMigrationVersions /= expectedMigrationVersions) $ do
      error $ "Migrations for table '" ++ tblNameString table ++ "'are wrong " ++ show presentMigrationVersions ++ " expected " ++ show expectedMigrationVersions

  versions <- mapM checkTableVersion tables
  let tablesWithVersions = zip tables (map (fromMaybe 0) versions)


  if all ((==) 0 . snd) tablesWithVersions
    then do -- no tables are present, create everything from scratch
      logger "Creating tables..."
      mapM_ createTable tables
      logger "Creating tables...done"

    else do -- migration mode

      forM_ tablesWithVersions $ \(table,ver) -> when (tblVersion table /= ver) $ do
        case L.find (\m -> tblNameString (mgrTable m) == tblNameString table) migrations of
          Nothing -> do
            error $ "No migrations found for table '" ++ tblNameString table ++ "', cannot migrate " ++ show ver ++ "->" ++ show (tblVersion table)
          Just m | mgrFrom m > ver -> do
            error $ "Earliest migration for table '" ++ tblNameString table ++ "' is from version " ++ show (mgrFrom m) ++ ", cannot migrate " ++ show ver ++ "->" ++ show (tblVersion table)
          Just _ -> return ()

      mapM_ (normalizePropertyNames logger) tables

      let migrationsToRun = filter (\m -> any (\(t, from) -> tblName (mgrTable m) == tblName t && mgrFrom m >= from) tablesWithVersions) migrations

      -- run migrations, if necessary
      when (not . null $ migrationsToRun) $ do
        logger "Running migrations..."
        forM_ migrationsToRun $ \migration -> do
          logger $ arrListTable (mgrTable migration) ++ show (mgrFrom migration) ++ "->" ++ show (mgrFrom migration +1)
          mgrDo migration
          runQuery_ $ sqlUpdate "table_versions" $ do
            sqlSet "version" $ succ (mgrFrom migration)
            sqlWhereEq "name" $ tblNameString (mgrTable migration)
        logger "Running migrations... done."

normalizePropertyNames :: (MonadDB m, MonadThrow m) => (String -> m ()) -> Table -> m ()
normalizePropertyNames logger table@Table{..} = do
  runQuery_ $ sqlGetPrimaryKey table
  pk <- join <$> fetchMaybe fetchPrimaryKey
  runQuery_ $ sqlGetIndexes table
  indexes <- fetchMany fetchTableIndex
  runQuery_ $ sqlGetForeignKeys table
  fkeys <- fetchMany fetchForeignKey
  let renames = concat [
          normalizePK pk
        , concatMap normalizeIndex indexes
        , concatMap normalizeFK fkeys
        ]
  when (not . null $ renames) $ do
    logger $ arrListTable table ++ "normalizing property names..."
    forM_ renames runQuery_
  where
    normalizePK :: Maybe (PrimaryKey, RawSQL ()) -> [RawSQL ()]
    normalizePK Nothing = []
    normalizePK (Just (_, name)) = case pkName tblName of
      pkname
        | pkname == name -> []
        | otherwise -> ["ALTER INDEX" <+> name <+> "RENAME TO" <+> pkname]

    normalizeIndex :: (TableIndex, RawSQL ()) -> [RawSQL ()]
    normalizeIndex (idx, name) = case indexName tblName idx of
      idxname
        | idxname == name -> []
        | otherwise -> ["ALTER INDEX" <+> name <+> "RENAME TO" <+> idxname]

    normalizeFK :: (ForeignKey, RawSQL ()) -> [RawSQL ()]
    normalizeFK (fk, name) = case fkName tblName fk of
      fkname
        | fkname == name -> []
        | otherwise -> [sqlAlterTable tblName [
            "DROP CONSTRAINT" <+> name
          , sqlAddFK tblName fk
          ]
        ]

checkTableVersion :: (MonadDB m, MonadThrow m) => Table -> m (Maybe Int32)
checkTableVersion table = do
  doesExist <- runQuery01 . sqlSelect "pg_catalog.pg_class c" $ do
    sqlResult "TRUE"
    sqlLeftJoinOn "pg_catalog.pg_namespace n" "n.oid = c.relnamespace"
    sqlWhereEq "c.relname" $ tblNameString table
    sqlWhere "pg_catalog.pg_table_is_visible(c.oid)"
  if doesExist
    then do
      runQuery_ $ "SELECT version FROM table_versions WHERE name =" <?> tblNameString table
      mver <- fetchMaybe unSingle
      case mver of
        Just ver -> return $ Just ver
        Nothing  -> error $ "Table '" ++ tblNameString table ++ "' is present in the database, but there is no corresponding version info in 'table_versions'."
    else do
      return Nothing

-- *** TABLE STRUCTURE ***

sqlGetTableID :: Table -> SQL
sqlGetTableID table = parenthesize . toSQLCommand $
  sqlSelect "pg_catalog.pg_class c" $ do
    sqlResult "c.oid"
    sqlLeftJoinOn "pg_catalog.pg_namespace n" "n.oid = c.relnamespace"
    sqlWhereEq "c.relname" $ tblNameString table
    sqlWhere "pg_catalog.pg_table_is_visible(c.oid)"

-- *** PRIMARY KEY ***

sqlGetPrimaryKey :: Table -> SQL
sqlGetPrimaryKey table = toSQLCommand . sqlSelect "pg_catalog.pg_constraint c" $ do
  sqlResult "c.conname::text"
  sqlResult "array(SELECT a.attname::text FROM pg_catalog.pg_attribute a WHERE a.attrelid = c.conrelid AND a.attnum = ANY (c.conkey)) as columns" -- list of affected columns
  sqlWhereEq "c.contype" 'p'
  sqlWhereEqSql "c.conrelid" $ sqlGetTableID table

fetchPrimaryKey :: (String, Array1 String) -> Maybe (PrimaryKey, RawSQL ())
fetchPrimaryKey (name, Array1 columns) = (, unsafeSQL name)
  <$> (pkOnColumns $ map unsafeSQL columns)

-- *** CHECKS ***

sqlGetChecks :: Table -> SQL
sqlGetChecks table = toSQLCommand . sqlSelect "pg_catalog.pg_constraint c" $ do
  sqlResult "c.conname::text"
  sqlResult $  "regexp_replace(pg_get_constraintdef(c.oid, true), 'CHECK \\((.*)\\)', '\\1') as body" -- check body
  sqlWhereEq "c.contype" 'c'
  sqlWhereEqSql "c.conrelid" $ sqlGetTableID table

fetchTableCheck :: (String, String) -> TableCheck
fetchTableCheck (name, condition) = TableCheck {
  chkName = unsafeSQL name
, chkCondition = unsafeSQL condition
}

-- *** INDEXES ***

sqlGetIndexes :: Table -> SQL
sqlGetIndexes table = toSQLCommand . sqlSelect "pg_catalog.pg_class c" $ do
  sqlResult "c.relname::text" -- index name
  sqlResult "array(SELECT a.attname::text FROM pg_catalog.pg_attribute a WHERE a.attrelid = i.indexrelid ORDER BY attnum) " -- array of affected columns
  sqlResult "i.indisunique" -- is it unique?
  sqlResult "CASE WHEN pg_get_indexdef(i.indexrelid, 0, true) LIKE '%WHERE%' THEN regexp_replace(pg_get_indexdef(i.indexrelid, 0, true), '.*WHERE (.*)', '\\1') ELSE NULL END" -- if partial, get constraint def
  sqlJoinOn "pg_catalog.pg_index i" "c.oid = i.indexrelid"
  sqlLeftJoinOn "pg_catalog.pg_constraint r" "r.conindid = i.indexrelid"
  sqlWhereEqSql "i.indrelid" $ sqlGetTableID table
  sqlWhereIsNULL "r.contype" -- fetch only "pure" indexes

fetchTableIndex :: (String, Array1 String, Bool, Maybe String) -> (TableIndex, RawSQL ())
fetchTableIndex (name, Array1 columns, unique, mconstraint) = (TableIndex {
  idxColumns = map unsafeSQL columns
, idxUnique = unique
, idxWhere = unsafeSQL `liftM` mconstraint
}, unsafeSQL name)

-- *** FOREIGN KEYS ***

sqlGetForeignKeys :: Table -> SQL
sqlGetForeignKeys table = toSQLCommand . sqlSelect "pg_catalog.pg_constraint r" $ do
  sqlResult "r.conname::text" -- fk name
  sqlResult "array(SELECT a.attname::text FROM pg_catalog.pg_attribute a WHERE a.attrelid = r.conrelid AND a.attnum = ANY (r.conkey))" -- constrained columns
  sqlResult "c.relname::text" -- referenced table
  sqlResult "array(SELECT a.attname::text FROM pg_catalog.pg_attribute a WHERE a.attrelid = r.confrelid AND a.attnum = ANY (r.confkey)) as refcolumns" -- referenced columns
  sqlResult "r.confupdtype" -- on update
  sqlResult "r.confdeltype" -- on delete
  sqlResult "r.condeferrable" -- deferrable?
  sqlResult "r.condeferred" -- initially deferred?
  sqlJoinOn "pg_catalog.pg_class c" "c.oid = r.confrelid"
  sqlWhereEqSql "r.conrelid" $ sqlGetTableID table
  sqlWhereEq "r.contype" 'f'

fetchForeignKey :: (String, Array1 String, String, Array1 String, Char, Char, Bool, Bool) -> (ForeignKey, RawSQL ())
fetchForeignKey (name, Array1 columns, reftable, Array1 refcolumns, on_update, on_delete, deferrable, deferred) = (ForeignKey {
  fkColumns = S.fromList . map unsafeSQL $ columns
, fkRefTable = unsafeSQL reftable
, fkRefColumns = S.fromList . map unsafeSQL $ refcolumns
, fkOnUpdate = charToForeignKeyAction on_update
, fkOnDelete = charToForeignKeyAction on_delete
, fkDeferrable = deferrable
, fkDeferred = deferred
}, unsafeSQL name)
  where
    charToForeignKeyAction c = case c of
      'a' -> ForeignKeyNoAction
      'r' -> ForeignKeyRestrict
      'c' -> ForeignKeyCascade
      'n' -> ForeignKeySetNull
      'd' -> ForeignKeySetDefault
      _   -> error $ "Invalid foreign key action code: " ++ show c

-- *** UTILS ***

tblNameString :: Table -> String
tblNameString = sqlToString . tblName

sqlToString :: RawSQL () -> String
sqlToString = BSU.toString . unRawSQL

checkEquality :: (Eq t, Show t) => String -> [t] -> [t] -> ValidationResult
checkEquality pname defs props = case (defs L.\\ props, props L.\\ defs) of
  ([], []) -> mempty
  (def_diff, db_diff) -> ValidationResult [concat [
      "Table and its definition have diverged and have "
    , show $ length db_diff
    , " and "
    , show $ length def_diff
    , " different "
    , pname
    , " each, respectively (table: "
    , show db_diff
    , ", definition: "
    , show def_diff
    , ")."
    ]]

checkNames :: Show t => (t -> RawSQL ()) -> [(t, RawSQL ())] -> ValidationResult
checkNames prop_name = mconcat . map check
  where
    check (prop, name) = case prop_name prop of
      pname
        | pname == name -> mempty
        | otherwise -> ValidationResult [ concat [
            "Property "
          , show prop
          , " has invalid name (expected: "
          , show pname
          , ", given: "
          , show name
          , ")."
          ]]

tableHasLess :: Show t => String -> t -> String
tableHasLess ptype missing = "Table in the database has *less* " ++ ptype ++ " than its definition (missing: " ++ show missing ++ ")"

tableHasMore :: Show t => String -> t -> String
tableHasMore ptype extra = "Table in the database has *more* " ++ ptype ++ " than its definition (extra: " ++ show extra ++ ")"

arrListTable :: Table -> String
arrListTable table = " -> " ++ tblNameString table ++ ": "
