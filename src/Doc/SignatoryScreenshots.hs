module Doc.SignatoryScreenshots
  ( SignatoryScreenshots(..)
  , emptySignatoryScreenshots
  , resolveReferenceScreenshotNames
  , getReferenceScreenshot
  , referencePath
  , validReferenceName
  ) where

import Control.Applicative ((<$>))
import Control.Monad.Base (MonadBase)
import Control.Monad.Trans (MonadIO, liftIO)
import Control.Monad.Trans.Control (MonadBaseControl)
import Text.JSON(Result(..), decode, JSValue(..), fromJSString)
import Text.JSON.FromJSValue
import Text.JSON.Gen (value, runJSONGen)
import Text.JSON.ToJSValue (ToJSValue(..))
import qualified Control.Exception.Lifted as E

import API.Monad (badInput)
import DB.SQL (SomeKontraException(..))
import Doc.Screenshot

data SignatoryScreenshots = SignatoryScreenshots
  { first         :: Maybe Screenshot
  , signing       :: Maybe Screenshot
  , reference     :: Maybe (Either String Screenshot)
  } deriving Show

getReferenceScreenshot :: SignatoryScreenshots -> Maybe Screenshot
getReferenceScreenshot s = either (const Nothing) Just =<< reference s

emptySignatoryScreenshots :: SignatoryScreenshots
emptySignatoryScreenshots = SignatoryScreenshots Nothing Nothing Nothing

instance FromJSValue SignatoryScreenshots where
  fromJSValue = do
    first <- fromJSValueField "first"
    signing <- fromJSValueField "signing"
    reference <- fromJSValueField "reference" >>= \case
      Just (JSString s) -> return $ Just $ Left $ fromJSString s
      Just (JSObject s) -> return $ Right <$> fromJSValue (JSObject s)
      _                 -> return Nothing
    return $ Just $ SignatoryScreenshots first signing reference

instance ToJSValue SignatoryScreenshots where
  toJSValue ss = runJSONGen $ do
    f "first" (fmap toJSValue . first)
    f "signing" (fmap toJSValue . signing)
    f "reference" (fmap (either toJSValue toJSValue) . reference)
   where f n v = case v ss of
                   Nothing -> return ()
                   Just s  -> value n s

referencePath :: String -> FilePath
referencePath name = "files/reference_screenshots/" ++ name ++ ".json"

validReferenceName :: String -> Bool
validReferenceName n = n `elem` ["author", "mobile", "standard"]

resolveReferenceScreenshotNames :: (MonadBase IO m, MonadBaseControl IO m, MonadIO m) => SignatoryScreenshots -> m SignatoryScreenshots
resolveReferenceScreenshotNames s =
  case reference s of
    Nothing -> return s
    Just (Right _) -> return s
    Just (Left name) | validReferenceName name -> do
        Ok json <- decode <$> (liftIO $ readFile $ referencePath name) `E.catch`
                    \E.SomeException{} -> bad
        Just r <- return $ fromJSValue json
        return $ s{ reference = Just (Right r) }
    _ -> bad
  where bad = E.throwIO . SomeKontraException $ badInput "Illegal reference screenshot name"
