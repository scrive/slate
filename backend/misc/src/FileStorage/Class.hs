module FileStorage.Class where

import Control.Monad.Reader
--import Control.Monad.State.Strict
--import Database.PostgreSQL.PQTypes
import qualified Data.ByteString as BS

-- | A monad in which we can store files.
--
-- Different layers of storage can be used and we stack them upon each other,
-- e.g. Memcache, Redis and S3.
--
-- For tests, we can fake this storage and store files in memory.
class Monad m => MonadFileStorage m where
  saveNewFile :: String        -- ^ Object key (URL-encoded)
              -> BS.ByteString -- ^ Contents (needs to be encrypted first)
              -> m (Either String ())

  getFileContents :: String -- ^ Object key (URL-encoded)
                  -> m (Either String BS.ByteString) -- ^ File contents

  deleteFile :: String -- ^ Object key (URL-encoded)
             -> m (Either String ())

--instance MonadFileStorage m => MonadFileStorage (ReaderT r m) where
--  saveNewFile url contents = lift $ saveNewFile url contents
--  getFileContents          = lift . getFileContents
--  deleteFile               = lift . deleteFile
--
--instance MonadFileStorage m => MonadFileStorage (StateT s m) where
--  saveNewFile url contents = lift $ saveNewFile url contents
--  getFileContents          = lift . getFileContents
--  deleteFile               = lift . deleteFile
--
--instance MonadFileStorage m => MonadFileStorage (DBT m) where
--  saveNewFile url contents = lift $ saveNewFile url contents
--  getFileContents          = lift . getFileContents
--  deleteFile               = lift . deleteFile
--
--instance MonadFileStorage m => MonadFileStorage (GuardTimeConfT m) where
--  saveNewFile url contents = lift $ saveNewFile url contents
--  getFileContents          = lift . getFileContents
--  deleteFile               = lift . deleteFile

instance {-# OVERLAPS #-} (MonadFileStorage m, MonadTrans t, Monad (t m))
    => MonadFileStorage (t m) where
  saveNewFile url contents = lift $ saveNewFile url contents
  getFileContents          = lift . getFileContents
  deleteFile               = lift . deleteFile
