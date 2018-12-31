module File.Storage
  ( MonadFileStorage
  , saveNewFile
  , getFileContents
  , getFileIDContents
  ) where

import Control.Monad.Base
import Control.Monad.Catch
import Control.Monad.Trans
import Crypto.RNG
import Data.Time
import Log
import System.FilePath
import qualified Crypto.Hash.SHA1 as SHA1
import qualified Data.ByteString.Base16 as Base16
import qualified Data.ByteString.Char8 as BS
import qualified Data.ByteString.Lazy as BSL
import qualified Data.ByteString.UTF8 as BSUTF
import qualified Network.HTTP as HTTP

import Crypto
import DB
import File.File
import File.Model
import FileStorage.Class (MonadFileStorage)
import Log.Identifier
import qualified FileStorage.Class as FS

-- | Create a new file, by uploading content straight to the underlying file
-- storage (S3 and caches.)
--
-- First creates an "empty" file using NewEmptyFileForAWS which has NULL
-- content, but other values set in database.
-- If upload succeeds, then it updates the file using FileMovedToAWS.
--
-- If the upload fails then the new NewEmptyFileForAWS is purged, and an
-- exception is thrown.
saveNewFile :: ( MonadBase IO m, MonadCatch m, MonadLog m, MonadDB m
               , MonadThrow m, CryptoRNG m, MonadFileStorage m )
            => String -> BS.ByteString -> m FileID
saveNewFile fName fContent = do
  startTime <- liftBase getCurrentTime
  emptyFile <- dbUpdate $ NewEmptyFileForAWS fName fContent
  let fid    = fileid emptyFile
      awsUrl = urlFromFile emptyFile
  Right aes <- mkAESConf <$> randomBytes 32 <*> randomBytes 16
  let encryptedContent = aesEncrypt aes fContent
  localData [identifier fid] $ do
    eRes <- try $ FS.saveNewContents awsUrl $ BSL.fromStrict encryptedContent
    case eRes of
      Right () -> do
        dbUpdate $ FileMovedToAWS fid awsUrl aes
        let file = emptyFile { filestorage = FileStorageAWS awsUrl aes }
        finishTime <- liftBase getCurrentTime
        logInfo "newFile: new file successfully created with content in S3" $ object [
            logPair_ file
          , "elapsed_time" .= (realToFrac $ diffUTCTime finishTime startTime :: Double)
          ]
        return fid
      Left err@(FS.FileStorageException msg) -> do
        let attnMsg = "newFile: failed to upload to AWS, purging file"
        logAttention attnMsg $ object [
            logPair_ emptyFile
          , "error" .= msg
          ]
        dbUpdate $ PurgeFile fid
        logAttention "newFileInAmazon: purged file" $ object [identifier fid]
        throwM err

-- | Get file contents from the underlying storage and decrypt the contents
-- returning them as BS.
getFileContents :: (MonadFileStorage m, MonadIO m, MonadLog m, MonadThrow m)
                => File -> m BS.ByteString
getFileContents File{ filestorage = FileStorageMemory contents } = return contents
getFileContents file@File{ fileid, filestorage = FileStorageAWS url aes } =
  localData [identifier fileid] $ do
    encrypted <- FS.getSavedContents url
    let contents = aesDecrypt aes $ BSL.toStrict encrypted
        checksum = SHA1.hash contents
    unless (checksum == filechecksum file) $ do
      logAttention "SHA1 checksums of file don't match" $ object
        [ logPair_ file
        ]
      throwM $ FS.FileStorageException $
        "SHA1 checksum of file doesn't match the one in the database"
    return contents

getFileIDContents :: ( MonadDB m, MonadFileStorage m, MonadIO m, MonadLog m
                     , MonadThrow m ) => FileID -> m BS.ByteString
getFileIDContents fid = do
  start <- liftIO getCurrentTime
  file <- dbQuery $ GetFileByFileID fid
  result <- getFileContents file
  stop <- liftIO getCurrentTime
  logInfo "getFileIDContents timing" $ object
    [ "duration" .= (realToFrac $ diffUTCTime stop start :: Double)
    , identifier fid
    ]
  return result

-- | Convert a file to Amazon URL. We use the following format:
--
-- > "file" </> fileid </> checksum </> filename
--
-- where filename and checksum will be urlencoded (percent encoded in UTF-8).
-- File name is preserved fully, that means you should supply file
-- extension already in place.
--
-- Note: Someday we might decide to publish temporarily externally
-- available links to files on Amazon. File names are already in
-- place, but Content-type is not, this will need to be fixed.
urlFromFile :: File -> String
urlFromFile File{filename, fileid, filechecksum} =
  -- here we use BSC.unpack, as HTTP.urlEncode
  -- does only %-escaping for 8bit values
  "file"
    </> show fileid
    </> (BS.unpack . Base16.encode $ filechecksum)
    </> (HTTP.urlEncode . BS.unpack . BSUTF.fromString $ filename)
