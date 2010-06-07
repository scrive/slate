{-# LANGUAGE ForeignFunctionInterface, CPP #-}


module SendMail where
import Control.Monad(msum,liftM,mzero,guard,MonadPlus(..),when)
import Control.Monad.Reader (ask)
import Control.Monad.Trans(liftIO, MonadIO,lift)
import Happstack.Server hiding (simpleHTTP)
import Happstack.Server.HSP.HTML (webHSP)
import Happstack.State (update,query,getRandomR)
import Network.HTTP (getRequest, getResponseBody, simpleHTTP)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy.UTF8 as BSL
import qualified Data.ByteString.Lazy as BSL
import qualified Data.ByteString.UTF8 as BS
import qualified Data.ByteString.Char8 as BSC

import qualified Data.Object.Json as Json
import qualified Network.Curl as Curl
import Data.Maybe
import Foreign.C.Types
import Foreign.Ptr
import Foreign.C.String
import HSX.XMLGenerator
import HSP
import Misc
import System.Process
import System.IO
import System.Directory
import Data.Array
import Data.Bits
import Data.Int
import Data.Char (chr,ord)
import Codec.Binary.Base64
import Data.List

sendMail :: BS.ByteString -- ^ full name
         -> BS.ByteString -- ^ email address
         -> BS.ByteString -- ^ title
         -> BS.ByteString -- ^ html contents
         -> BS.ByteString -- ^ attached pdf contents
         -- more arguments follow
         -> IO ()
sendMail fullname email title content attachmentcontent = do
  let mailto = BS.toString fullname ++ " <" ++ BS.toString email ++ ">"
#ifdef WINDOWS
  tmp <- getTemporaryDirectory
  let filename = tmp ++ "/Email-" ++ BS.toString email ++ ".eml"
  handle_in <- openBinaryFile filename WriteMode 
#else
  (Just handle_in,_,_,handle_process) <-
      createProcess (proc "sendmail" ["-i", mailto ]) { std_in = CreatePipe }
#endif
  -- FIXME: encoding issues
  let boundary = "skrivapa-mail-12-337331046" 
  let header = 
          "Subject: " ++ BS.toString title ++ "\r\n" ++
          "From: skrivaPa <info@skrivapa.se>\r\n" ++
          "MIME-Version: 1.0\r\n" ++
          "Content-Type: multipart/mixed; boundary=" ++ boundary ++ "\r\n" ++
          "\r\n"
  let header1 = "--" ++ boundary ++ "\r\n" ++
          "Content-type: text/html; charset=utf-8\r\n" ++
          "\r\n"
  let header2 = "\r\n--" ++ boundary ++ "\r\n" ++
          "Content-Disposition: inline; filename=\"" ++ BS.toString title ++".pdf\"\r\n" ++
          "Content-Type: application/pdf; name=\"" ++ BS.toString title ++ ".pdf\"\r\n" ++
          "Content-Transfer-Encoding: base64\r\n" ++
          "\r\n"
  let footer = "\r\n--" ++ boundary ++ "--\r\n"
  BS.hPutStr handle_in (BS.fromString header)
  BS.hPutStr handle_in (BS.fromString header1)
  BS.hPutStr handle_in content
  when (not (BS.null attachmentcontent)) $ do
    BS.hPutStr handle_in (BS.fromString header2)
    BS.hPutStr handle_in (BSC.pack $ concat $ intersperse "\r\n" $ chop 72 $ encode $ BS.unpack attachmentcontent)
  BS.hPutStr handle_in (BS.fromString footer)
  
  hFlush handle_in
  hClose handle_in
#ifdef WINDOWS
  openDocument filename
#else
  waitForProcess handle_process
#endif
  return ()

