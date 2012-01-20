module User.Password where

import Control.Monad.IO.Class
import System.Random (newStdGen, randoms)
import qualified Data.ByteString as BS
import qualified Data.Digest.SHA256 as D

import DB.Types

data Password = Password {
    pwdHash :: Binary
  , pwdSalt :: Binary
  } deriving (Eq, Ord, Show)

createPassword :: MonadIO m => BS.ByteString -> m Password
createPassword password = liftIO $ do
  salt <- makeSalt
  return Password {
      pwdHash = hashPassword password salt
    , pwdSalt = salt
  }
  where
    makeSalt = do
      rng <- newStdGen
      return . Binary . BS.pack . take 10 $ map fromIntegral (randoms rng :: [Int])

hashPassword :: BS.ByteString -> Binary -> Binary
hashPassword password salt =
  Binary . BS.pack . D.hash . BS.unpack $ unBinary salt `BS.append` password

verifyPassword :: Maybe Password -> BS.ByteString -> Bool
verifyPassword Nothing _ = False
verifyPassword (Just Password{pwdHash, pwdSalt}) password =
  pwdHash == hashPassword password pwdSalt
