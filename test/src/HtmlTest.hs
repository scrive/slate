{-# LANGUAGE CPP #-}
{-# OPTIONS_GHC -Wall -fwarn-tabs -fwarn-incomplete-record-updates
-fwarn-monomorphism-restriction -fwarn-unused-do-bind -Werror #-}

module HtmlTest where


import Test.Framework (Test, testGroup, defaultMain)
import Test.Framework.Providers.HUnit (testCase)
import Test.HUnit (assertFailure, assertBool, Assertion)
import Text.XML.HaXml.Parse (xmlParse')
import Text.XML.HaXml.Posn
import Text.XML.HaXml.Types
import System.IO

import Templates.TemplatesFiles

main :: IO ()
main = do
    hSetEncoding stdout utf8
    hSetEncoding stderr utf8
    defaultMain tests

tests :: [Test]
tests = [ testGroup "Html" htmlTests
        ]


htmlTests :: [Test]
htmlTests = 
    [ testGroup "static checks"
        [ testCase "templates make valid xml" testValidXml ]
    ]

testValidXml :: Assertion
testValidXml = do
  templates <- mapM getTemplates templatesFilesPath
  _ <- mapM assertTemplateIsValidXML . filter isIncluded $ concat templates
  assertSuccess
  where
    excludedTemplates = ["paymentsadminpagesuperuser","bodystart","bodyend"]
    isIncluded (name, _) = not $ name `elem` excludedTemplates

assertTemplateIsValidXML :: (String,String) -> Assertion
assertTemplateIsValidXML t =
  case parseTemplateAsXML t of
    Left msg -> assertFailure msg
    Right _ -> assertSuccess

parseTemplateAsXML :: (String,String) -> Either String (Document Posn)
parseTemplateAsXML (name, rawtxt) =
  let preparedtxt = "<template>\n" ++ (clearTemplatingStuff rawtxt) ++ "\n</template>"
      prettyprinttxt = unlines . zipWith mklinewithno ([1..]::[Int]) $ lines preparedtxt
      mklinewithno no line --okay, i did indenting in a horrible way, it's just a test!
        | no<10  = (show no) ++ ".    |" ++ line
        | no<100  = (show no) ++ ".   |" ++ line
        | no<1000  = (show no) ++ ".  |" ++ line
        | otherwise = (show no) ++ ". |" ++ line
  in case xmlParse' name preparedtxt of
    Left msg -> Left $ msg ++ "\n" ++ prettyprinttxt
    r@(Right _) -> r

clearTemplatingStuff :: String -> String
clearTemplatingStuff = clearTemplatingStuff' In_Html


--this stuff is a very basic way of clearing out the templating stuff
--probably a better way
data ClearState = In_Html | In_Dollars

clearTemplatingStuff' :: ClearState -> String -> String
clearTemplatingStuff' _ [] = []
clearTemplatingStuff' In_Html ('\\':'$':xs) = '$' : clearTemplatingStuff' In_Html xs
clearTemplatingStuff' In_Html ('$':xs) = clearTemplatingStuff' In_Dollars xs
clearTemplatingStuff' In_Html ('}':';':xs) = clearTemplatingStuff' In_Dollars xs
clearTemplatingStuff' In_Html ('}':':':xs) = clearTemplatingStuff' In_Dollars xs
clearTemplatingStuff' In_Html ('}':'$':xs) = clearTemplatingStuff' In_Html xs
clearTemplatingStuff' In_Html (x:xs) = x : clearTemplatingStuff' In_Html xs 
clearTemplatingStuff' In_Dollars ('$':xs) = clearTemplatingStuff' In_Html xs
clearTemplatingStuff' In_Dollars ('|':xs) = clearTemplatingStuff' In_Html xs
clearTemplatingStuff' In_Dollars (_:xs) = clearTemplatingStuff' In_Dollars xs

assertSuccess :: Assertion
assertSuccess = assertBool "not success?!" True
