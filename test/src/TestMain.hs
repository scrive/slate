{-# LANGUAGE CPP #-}
module TestMain where

import Control.Applicative
import Data.Char
import Data.Either
import Database.HDBC.PostgreSQL
import System.Environment.UTF8
import System.IO
import Test.Framework
import qualified Log

import AppDB
import DB.Checks
import DB.Classes
import DB.Nexus
import Control.Exception

-- Note: if you add new testsuites here, please add them in a similar
-- manner to existing ones, i.e. wrap them around ifdefs and add appropriate
-- flags to kontrakcja.cabal to allow possibility of disabling tests selectively
-- if e.g. for some reason they stop compiling. Also, please keep them in
-- alphabetic order.

#ifndef NO_COMPANYSTATE
import CompanyStateTest
#endif
#ifndef NO_DOCSTATE
import DocStateTest
#endif
#ifndef NO_DOCCONTROL
import DocControlTest
#endif
#ifndef NO_DOCSTATEQUERY
import DocStateQueryTest
#endif
#ifndef NO_HTML
import HtmlTest
#endif
#ifndef NO_INPUTVALIDATION
import InputValidationTest
#endif
#ifndef NO_INTEGRATIONAPI
import IntegrationAPITest
#endif
#ifndef NO_LOGIN
import LoginTest
#endif
#ifndef NO_SIGNUP
import SignupTest
#endif
#ifndef NO_ACCOUNTINFO
import AccountInfoTest
#endif
#ifndef NO_MAILAPI
import MailAPITest
#endif
#ifndef NO_REDIRECT
import RedirectTest
#endif
#ifndef NO_SERVICESTATE
import ServiceStateTest
#endif
#ifndef NO_TRUSTWEAVER
import TrustWeaverTest
#endif
#ifndef NO_USERSTATE
import UserStateTest
#endif
#ifndef NO_USERHISTORY
import UserHistoryTest
#endif
#ifndef NO_CSVUTIL
import CSVUtilTest
#endif
#ifndef NO_SIMPLEEMAIL
import SimpleMailTest
#endif
#ifndef NO_LOCALE
import LocaleTest
#endif
#ifndef NO_COMPANYACCOUNTS
import CompanyAccountsTest
#endif
#ifndef NO_MAILS
import MailsTest
#endif
#ifndef NO_MAILS
import APICommonsTest
#endif
#ifndef NO_JSON
import JSONUtilTest
#endif
#ifndef NO_SQLUTILS
import SQLUtilsTest
#endif

#ifndef NO_FILE
import FileTest
#endif

#ifndef NO_DOCJSON
import Doc.TestJSON
#endif

#ifndef NO_STATS
import StatsTest
#endif

allTests :: Nexus -> [(String, [String] -> Test)]
allTests conn = tail tests
  where
    tests = [
        undefined
#ifndef NO_COMPANYSTATE
      , ("companystate", const $ companyStateTests conn)
#endif
#ifndef NO_DOCSTATE
      , ("docstate", const $ docStateTests conn)
#endif
#ifndef NO_DOCCONTROL
      , ("doccontrol", const $ docControlTests conn)
#endif
#ifndef NO_DOCSTATEQUERY
      , ("docstatequery", const $ docStateQueryTests)
#endif
#ifndef NO_HTML
      , ("html", const $ htmlTests)
#endif
#ifndef NO_INPUTVALIDATION
      , ("inputvalidation", const $ inputValidationTests)
#endif
#ifndef NO_INTEGRATIONAPI
      , ("integrationapi", const $ integrationAPITests conn)
#endif
#ifndef NO_LOGIN
      , ("login", const $ loginTests conn)
#endif
#ifndef NO_SIGNUP
      , ("signup", const $ signupTests conn)
#endif
#ifndef NO_ACCOUNTINFO
     , ("accountinfo", const $ accountInfoTests conn)
#endif
#ifndef NO_MAILAPI
      , ("mailapi", const $ mailApiTests conn)
#endif
#ifndef NO_REDIRECT
      , ("redirect", const $ redirectTests)
#endif
#ifndef NO_SERVICESTATE
      , ("servicestate", const $ serviceStateTests conn)
#endif
#ifndef NO_TRUSTWEAVER
      -- everything fails for trustweaver, so commenting out for now
      , ("trustweaver", const $ trustWeaverTests)
#endif
#ifndef NO_USERSTATE
      , ("userstate", const $ userStateTests conn)
#endif
#ifndef NO_USERSTATE
      , ("userhistory", const $ userHistoryTests conn)
#endif
#ifndef NO_CSVUTIL
      , ("csvutil", const $ csvUtilTests)
#endif
#ifndef NO_SIMPLEEMAIL
      , ("simplemail", const $ simpleMailTests)
#endif
#ifndef NO_LOCALE
      , ("locale", const $ localeTests conn)
#endif
#ifndef NO_COMPANYACCOUNTS
      , ("companyaccounts", const $ companyAccountsTests conn)
#endif
#ifndef NO_MAILS
      , ("mails", mailsTests conn )
#endif
#ifndef NO_MAILS
      , ("apicommons", const $ apiCommonsTest )
#endif
#ifndef NO_JSON
      , ("jsonutil", const $ jsonUtilTests )
#endif
#ifndef NO_FILE
      , ("file", const $ fileTests conn )
#endif
#ifndef NO_DOCJSON
      , ("docjson", const $ documentJSONTests)
#endif
#ifndef NO_SQLUTILS
      , ("sqlutil", const $ sqlUtilsTests )
#endif
#ifndef NO_STATS
      , ("stats", const $ statsTests conn)
#endif
      ]

testsToRun :: Nexus -> [String] -> [Either String Test]
testsToRun _ [] = []
testsToRun conn (t:ts)
  | lt == "$" = []
  | lt == "all" = map (\(_,f) -> Right $ f params) (allTests conn) ++ rest
  | otherwise = case lookup lt (allTests conn) of
                  Just testcase -> Right (testcase params) : rest
                  Nothing       -> Left t : rest
  where
    lt = map toLower t
    rest = testsToRun conn ts
    params = drop 1 $ dropWhile (/= ("$")) ts

main :: IO ()
main = Log.withLogger $ do
  hSetEncoding stdout utf8
  hSetEncoding stderr utf8
  pgconf <- readFile "kontrakcja_test.conf"
  withPostgreSQL pgconf $ \conn' -> do
    conn <- mkNexus conn'
    ioRunDB conn $ performDBChecks Log.debug kontraTables kontraMigrations
    (args, tests) <- partitionEithers . testsToRun conn <$> getArgs

    -- defaultMainWithArgs does not feel like returning like a normal function
    -- so have to get around that 'feature'!!
    bracket_ (return ())
             (do 
               stats <- getNexusStats conn
               putStrLn $ "SQL: queries " ++ show (nexusQueries stats) ++ 
                          ", params " ++ show (nexusParams stats) ++
                          ", rows " ++ show (nexusRows stats) ++
                          ", values " ++ show (nexusValues stats))

             (defaultMainWithArgs tests args)
