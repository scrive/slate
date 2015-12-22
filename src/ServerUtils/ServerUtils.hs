module ServerUtils.ServerUtils (
     handleParseCSV
   , handleSerializeImage
   , handleTextToImage
   , brandedImage
  ) where

--import Happstack.Server hiding (dir, simpleHTTP)
import Control.Monad.Trans
import Data.Char (toLower)
import Data.Functor
import Happstack.Server hiding (dir, simpleHTTP)
import Log as Log
import Numeric
import System.Directory (getCurrentDirectory)
import System.Exit
import System.FilePath ((</>), takeBaseName)
import System.Path (secureAbsNormPath)
import System.Process hiding (readProcessWithExitCode)
import System.Process.ByteString.Lazy (readProcessWithExitCode)
import Text.JSON
import Text.JSON.Gen hiding (object)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Base64 as B64
import qualified Data.ByteString.Lazy as BSL
import qualified Data.ByteString.UTF8 as BS (fromString)
import qualified Data.ByteString.UTF8 as BSUTF8
import qualified Happstack.Server.Response as Web
import qualified Text.JSON.Gen as J

import Happstack.Fields
import Kontra
import KontraPrelude
import ServerUtils.BrandedImagesCache
import Util.CSVUtil
import Util.MonadUtils
import Utils.Directory
import qualified MemCache as MemCache

-- Read a csv file from POST, and returns a JSON with content
handleParseCSV :: Kontrakcja m => m JSValue
handleParseCSV = do
  input <- getDataFn' (lookInput "csv")
  res <- case input of
        Just(Input contentspec (Just filename) _ ) -> do
          content <- case contentspec of
                       Left filepath -> liftIO $ BSL.readFile filepath
                       Right content -> return content
          let _title = BS.fromString (takeBaseName filename)
          case parseCSV content of
                 Right (h:r) -> J.runJSONGenT $ do
                         J.value "header" $ h
                         J.value "rows" $ r
                 _ -> runJSONGenT $ J.value "parseError" True
        _ -> runJSONGenT $ J.value "parseError" True
  return res

-- Read an image file from POST, and returns a its content encoded with Base64
handleSerializeImage :: Kontrakcja m => m Response
handleSerializeImage = do
  fileinput <- getDataFn' (lookInput "logo")
  case fileinput of
    Nothing -> badRequest' "Missing file"
    Just (Input _ Nothing _) -> badRequest' "Missing file"
    Just (Input contentspec (Just filename) _contentType) -> do
      let hasExtension ext = ("." ++ ext) `isSuffixOf` map toLower filename
      if hasExtension "png" || hasExtension "jpg" || hasExtension "jpeg" then do
        content <- case contentspec of
          Left filepath -> liftIO $ BS.readFile filepath
          Right content' -> return $ BS.concat $ BSL.toChunks content'
        goodRequest $ runJSONGen $ value "logo_base64" $ showJSON $ B64.encode content
      else badRequest' "Not image"
 where badRequest' s = return $ (setHeader "Content-Type" "text/plain; charset=UTF-8" $ Web.toResponse $ (s :: String)) {rsCode = 400}
       goodRequest js = return $ (setHeader "Content-Type" "text/plain; charset=UTF-8" $ Web.toResponse $ encode js) {rsCode = 200}

-- Based on text, returns an image of this text, drawn using `handwriting` font.
-- Expected text, dimentions, font and format (base64 or plain) are passed as parameters.
handleTextToImage :: Kontrakcja m =>  m Response
handleTextToImage = do
    text <- fmap (take 50) $ guardJustM $ getField "text"
    (width::Int)  <- fst <$> (guardJustM $ join <$> fmap (listToMaybe . readDec) <$> getField "width")
    (height::Int) <- fst <$> (guardJustM $ join <$> fmap (listToMaybe . readDec) <$> getField "height")
    (font, fontSize) <- do
              mfont <- getField "font"
              return $ case mfont of
                        Just "JenniferLynne"    -> ("frontend/app/fonts/JenniferLynne.ttf",22)
                        Just "TalkingToTheMoon" -> ("frontend/app/fonts/TalkingToTheMoon.ttf",20)
                        _                       -> ("frontend/app/fonts/TheOnlyException.ttf",16)
    base64 <- isFieldSet "base64"
    transparent <- isFieldSet "transparent"
    left <- isFieldSet "left"

    mfcontent <- withSystemTempDirectory' "text_to_image" $ \tmppath -> do
      let fpath = tmppath ++ "/text_to_image.png"
      (_,_,_, drawer) <- liftIO $ createProcess $ proc "convert"
            [ "-size", (show width ++ "x" ++ show height)
            , "-background", if (transparent) then "transparent" else "white"
            , "-pointsize", show (pointSize width height (length text) fontSize)
            , "-gravity", if (left) then "West" else "Center"
            , "-font", font
            , "label:" ++ (if null text then " " else text)
            , "PNG32:" ++ fpath ]
      drawerexitcode <- liftIO $ waitForProcess drawer
      case drawerexitcode of
          ExitFailure msg -> do
            logInfo "text_to_image failed" $ object [
                "error" .= msg
              ]
            return Nothing
          ExitSuccess -> (liftIO $ BSL.readFile fpath) >>= (return . Just)
    case mfcontent of
         Just fcontent -> if base64
                             then ok $ toResponseBS (BSUTF8.fromString "text/plain") $ BSL.fromChunks [BSUTF8.fromString "data:image/png;base64,", B64.encode $ BSL.toStrict fcontent]
                             else ok $ setHeaderBS "Cache-Control" "max-age=600" $ toResponseBS (BSUTF8.fromString "image/png") $ fcontent
         Nothing -> internalError

-- Take any image and brand it by replacing black, non-transparent colors with the specified colour.
-- Expecting color and filename to be passed as parameters.
-- Color format should be #deadbe.
-- Filename is the basename of the file, brandedImage will find it in frontend/app/img/
brandedImage :: Kontrakcja m =>  m Response
brandedImage = do
    ctx <- getContext
    color <- fmap (take 12) $ guardJustM $ getField "color"
    file <- fmap (take 50) $ guardJustM $ getField "file"
    let key = BrandedImagesCacheKey { filename = file , color = color }
    let cache = ctxbrandedimagescache ctx
    mv <- MemCache.get key cache
    img <- if (ctxproduction ctx)
             then case mv of
               Just v -> return v
               Nothing -> do
                 bi <- brandImage file color
                 MemCache.put key bi cache
                 return bi
            else
              brandImage file color
    ok $ setHeaderBS "Cache-Control" "max-age=604800" $ toResponseBS (BSUTF8.fromString "image/png") $ img

brandImage :: Kontrakcja m => String -> String -> m BSL.ByteString
brandImage file color = do
    cwd <- liftIO getCurrentDirectory
    let imgDir = cwd </> "frontend/app/img"
    fpath <- guardJust $ secureAbsNormPath imgDir file
    (procResult, out, _) <- liftIO $ readProcessWithExitCode "convert" [fpath
                                                  , "-colorspace", "Gray"
                                                  , "+level-colors", color ++ ",white"
                                                  , "-"] ""
    case procResult of
      ExitFailure msg -> do
        logInfo "Problem branding signview image" $ object [
            "error" .= msg
          ]
        internalError
      ExitSuccess -> return out




-- Point scale - some heuristic for pointsize, based on size of image, type of font and lenght of text.
-- Result should be point size that will result in best fit. It is also expected that this value does not change much on text lenght change.
-- Magic font dependend value sugests what point size will fill in 30x30 squere.

pointSize :: Int -> Int  -> Int -> Int -> Int
pointSize width height textl fontSize =
    min ((height - 20)  * fontSize `div` 30) ((width `div` (textl + 1)) * fontSize `div` 11)
