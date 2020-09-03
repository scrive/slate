module EID.EIDService.Communication (
    createTransactionWithEIDService
  , startTransactionWithEIDService
  , startTransactionWithEIDServiceWithStatus
  , getTransactionFromEIDService
  , HttpErrorCode(..)
  ) where

import Control.Monad.Base
import Control.Monad.Trans.Control
import Data.Aeson
import Data.Bifunctor
import Data.ByteString as BS
import Data.ByteString.Internal as BS
import Log
import System.Exit
import qualified Data.ByteString.Lazy as BSL
import qualified Data.Text as T
import qualified Data.Text.Encoding as T

import EID.EIDService.Conf
import EID.EIDService.Types
import Kontra hiding (InternalError)
import Log.Identifier
import Log.Utils
import Utils.IO

data CallType = Create | Start | Fetch deriving Show

newtype HttpErrorCode = HttpErrorCode
  {
    unStatus :: Int
  } deriving (Show, Read)

guardExitCode
  :: (MonadLog m, MonadBase IO m)
  => CallType
  -> Text
  -> (ExitCode, BSL.ByteString, BSL.ByteString)
  -> m ()
guardExitCode calltype provider (exitcode, stdout, stderr) = case exitcode of
  ExitFailure msg -> do
    let verb = T.toLower . T.pack $ show calltype
    logAttention
        ("Failed to " <> verb <> " new transaction (eidservice/" <> provider <> ")")
      $ object
          [ "stdout" `equalsExternalBSL` stdout
          , "stderr" `equalsExternalBSL` stderr
          , "errorMessage" .= msg
          ]
    internalError
  ExitSuccess -> do
    let verb = T.pack $ show calltype
    logInfo ("Success: " <> verb <> " new transaction (eidservice/" <> provider <> ")")
      $ object ["stdout" `equalsExternalBSL` stdout, "stderr" `equalsExternalBSL` stderr]

cURLCall
  :: (MonadBase IO m, MonadLog m)
  => EIDServiceConf
  -> CallType
  -> EIDServiceTransactionProvider
  -> Text
  -> Maybe BSL.ByteString
  -> m (Either HttpErrorCode BSL.ByteString)
cURLCall conf calltype provider endpoint mjsonData = do
  let verb = case calltype of
        Create -> "POST"
        Start  -> "POST"
        Fetch  -> "GET"
  (exitcode, stdout, stderr) <-
    readCurl
        (  ["-X", verb]
        ++ ["-H", "Authorization: Bearer " <> T.unpack (eidServiceToken conf)]
        ++ ["-H", "Content-Type: application/json"]
        ++ ["-i"]
        ++ (if isJust mjsonData then ["--data", "@-"] else [])
        ++ [T.unpack $ eidServiceUrl conf <> "/api/v1/transaction/" <> endpoint]
        )
      $ fromMaybe BSL.empty mjsonData
  guardExitCode calltype (toEIDServiceProviderName provider) (exitcode, stdout, stderr)
  -- headers and status line are divided by one empty line - we are doing a break on this
  let (statusAndHeaders, content) =
        second (BS.drop 4) . BS.breakSubstring "\r\n\r\n" $ BSL.toStrict stdout
  case getHttpStatusFromStatusLine $ BSL.fromStrict statusAndHeaders of
    Just 200   -> return . Right $ BSL.fromStrict content
    Just other -> return . Left $ HttpErrorCode other
    Nothing    -> do
      logAttention_ "Can't parse http status line"
      internalError
  where
    getHttpStatusFromStatusLine :: BSL.ByteString -> Maybe Int
    getHttpStatusFromStatusLine bs = case BSL.split (BS.c2w ' ') bs of
      _ : statusCodeS : _ -> maybeRead . T.decodeUtf8 . BSL.toStrict $ statusCodeS
      _                   -> Nothing

createTransactionWithEIDService
  :: (Kontrakcja m, FromJSON b)
  => EIDServiceConf
  -> CreateEIDServiceTransactionRequest
  -> m b
createTransactionWithEIDService conf req = do
  (cURLCall conf Create (cestProvider req) "new" . Just $ encode req) >>= \case
    Right respContent -> case decode respContent of
      Nothing -> do
        logAttention_ $ "Failed to read create transaction response" <> showt respContent
        internalError
      Just resp -> return resp
    Left httpError -> do
      logAttention_ $ "Transaction creationg failed with error code " <> showt httpError
      internalError

startTransactionWithEIDService
  :: (Kontrakcja m, FromJSON b)
  => EIDServiceConf
  -> EIDServiceTransactionProvider
  -> EIDServiceTransactionID
  -> m b
startTransactionWithEIDService conf provider tid =
  startTransactionWithEIDServiceWithStatus conf provider tid >>= \case
    Right resp   -> return resp
    Left  status -> do
      logAttention_ $ "EID service responded with " <> showt status <> "status, failing"
      internalError

startTransactionWithEIDServiceWithStatus
  :: (Kontrakcja m, FromJSON b)
  => EIDServiceConf
  -> EIDServiceTransactionProvider
  -> EIDServiceTransactionID
  -> m (Either HttpErrorCode b)
startTransactionWithEIDServiceWithStatus conf provider tid =
  localData [identifier tid] $ do
    let endpoint = fromEIDServiceTransactionID tid <> "/start"
    (cURLCall conf Start provider endpoint . Just . encode . toJSON $ object []) >>= \case
      Right respContent -> do
        case decode respContent of
          Nothing -> do
            logAttention_ "Failed to parse start transaction response"
            -- TODO: Get rid of all the blank, useless internalError calls in EID.EIDService
            internalError
          Just resp -> return $ Right resp
      Left code -> do
        return . Left $ code

getTransactionFromEIDService
  :: (MonadLog m, MonadBaseControl IO m, FromJSON b)
  => EIDServiceConf
  -> EIDServiceTransactionProvider
  -> EIDServiceTransactionID
  -> m (Maybe b)
getTransactionFromEIDService conf provider tid = localData [identifier tid] $ do
  let endpoint = fromEIDServiceTransactionID tid
  cURLCall conf Fetch provider endpoint Nothing >>= \case
    Right respContent -> do
      case eitherDecode respContent of
        Right transaction -> return $ Just transaction
        Left  errMessage  -> do
          logAttention_
            $  "There was an error while decoding the transaction"
            <> showt errMessage
          return Nothing
    Left httpErrorCode -> do
      logAttention_ $ "Getting transaction failed with error code " <> showt httpErrorCode
      internalError
