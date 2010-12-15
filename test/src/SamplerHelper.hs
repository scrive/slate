module SamplerHelper (sampleMail, sampleFlashMsg, sampleView) where

import Test.HUnit (assert, assertEqual, assertFailure, Assertion(..))
import Test.Framework (Test, testGroup)
import Test.Framework.Providers.HUnit (testCase)

import Templates
import SendMail

import System.Directory
import System.FilePath

import qualified Data.ByteString.UTF8 as BS
import qualified Data.ByteString as BS

sampleMail name action = sample name "mail" action mailSaver

sampleFlashMsg name action = sample name "flash_msg" action stringSaver

sampleView name action = sample name "view" action stringSaver

sample name suffix action saver = withSampleDirectory $ \tmp -> do
   t <- readTemplates
   content <- action t
   let file = tmp ++ "/" ++ name ++ "_" ++ suffix ++ ".html"
   saver file content 
   assert True

mailSaver file mail = BS.writeFile file (content mail)

stringSaver file str = writeFile file ("<html><head><meta http-equiv=\"content-type\" content=\"text/html; charset=utf-8\"/></head><body>" ++ str ++ "</body></html>")

withSampleDirectory :: (FilePath -> IO a) -> IO a
withSampleDirectory action = do 
  tmp <- getTemporaryDirectory
  let sampleDir = tmp </> "kontrakcja-content-samples"
  createDirectoryIfMissing False sampleDir
  action sampleDir
  
