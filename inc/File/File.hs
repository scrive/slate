module File.File 
    ( File(..)
    , FileStorage(..)
    ) where

import Data.Typeable
import qualified Data.ByteString as BS

import Crypto
import File.FileID

data FileStorage =
    FileStorageMemory BS.ByteString AESConf
  | FileStorageAWS String String AESConf -- ^ bucket, url inside bucket, aes key/iv
    deriving (Eq, Ord, Show, Typeable)

data File = File {
    fileid       :: FileID
  , filename     :: String
  -- if there is conversion error from sql, detect it immediately
  , filestorage  :: !FileStorage
  , filechecksum :: Maybe BS.ByteString
  } deriving (Typeable)

instance Eq File where
  a == b = fileid a == fileid b

instance Ord File where
  compare a b | fileid a == fileid b = EQ
              | otherwise = compare (fileid a, filename a)
                                    (fileid b, filename b)
instance Show File where
  show = filename
