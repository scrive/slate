{-# LANGUAGE OverloadedStrings #-}
module DocStateTest (docStateTests) where

import Test.HUnit (assert, assertFailure, Assertion, assertBool, assertEqual)
import Test.Framework
import Test.Framework.Providers.HUnit (testCase)

import StateHelper
import User.Password
import User.UserState
import Doc.DocState
import Doc.DocUtils
import MinutesTime
import Happstack.State
import Misc
import Payments.PaymentsState as Payments

import Util.SignatoryLinkUtils
import qualified Data.ByteString.UTF8 as BS
import qualified Data.ByteString as BS
import Data.Maybe
import Control.Monad.Trans

import Data.List

docStateTests :: Test
docStateTests = testGroup "DocState" [
  testThat "create document and check invariants" testNewDocumentDependencies,
  testThat "can create new document and read it back with the returned id" testDocumentCanBeCreatedAndFetchedByID,
  testThat "can create new document and read it back with GetDocuments" testDocumentCanBeCreatedAndFetchedByAllDocs,
  testThat "when I call update document, it doesn't change the document id" testDocumentUpdateDoesNotChangeID,
  testThat "when I call update document, i can change the title" testDocumentUpdateCanChangeTitle,
  testThat "when I attach a file to a real document, it ALWAYS returns Right" testDocumentAttachAlwaysRight,
  testThat "when I attach a file to a bad docid, it ALWAYS returns Left" testNoDocumentAttachAlwaysLeft,
  testThat "when I attach a file, the file is attached" testDocumentAttachHasAttachment
                ]

testThat :: String -> Assertion -> Test
testThat s a = testCase s (withTestState a)

testNewDocumentDependencies :: Assertion
testNewDocumentDependencies = do
  -- setup
  mt <- whatTimeIsIt
  author <- assumingBasicUser
  -- execute
  doc <- update $ NewDocument author "Test New Document No Company" (Signable Contract) mt
  -- assert
  assertInvariants doc
  
testDocumentCanBeCreatedAndFetchedByID :: Assertion
testDocumentCanBeCreatedAndFetchedByID = do
  -- setup
  mt <- whatTimeIsIt
  author <- assumingBasicUser

  doc <- update $ NewDocument author "Test New Document No Company" (Signable Contract) mt
      
  mdoc <- query $ GetDocumentByDocumentID (documentid doc)
  -- assert
  case mdoc of
    Just resdoc -> assert $ sameDocID doc resdoc
    Nothing -> assertFailure "Could not read in new document I just created."

testDocumentCanBeCreatedAndFetchedByAllDocs :: Assertion
testDocumentCanBeCreatedAndFetchedByAllDocs = do
  -- setup
  mt <- whatTimeIsIt
  author <- assumingBasicUser
  -- execute
  doc <- update $ NewDocument author "Test New Document No Company" (Signable Contract) mt
  docs <- query $ GetDocuments Nothing
      
  -- assert
  case find (sameDocID doc) docs of
    Just _ -> assertSuccess
    Nothing -> assertFailure "Could not read in new document I just created."

testDocumentUpdateDoesNotChangeID :: Assertion
testDocumentUpdateDoesNotChangeID = do
  -- setup
  mt <- whatTimeIsIt
  author <- assumingBasicUser
  doc <- assumingBasicContract mt author
  --execute
  let sd = signatoryDetailsFromUser author
  enewdoc <- update $ UpdateDocument mt (documentid doc) "Test Document" [] Nothing "" (sd, [SignatoryAuthor, SignatoryPartner], (userid author, Nothing)) [EmailIdentification] Nothing AdvancedFunctionality 
  --assert
  case enewdoc of
    Left msg -> assertFailure $ "Could not run UpdateDocument: " ++ msg
    Right newdoc -> assertEqual "document ids should be equal" (documentid doc) (documentid newdoc)

testDocumentUpdateCanChangeTitle :: Assertion
testDocumentUpdateCanChangeTitle = do
  -- setup
  mt <- whatTimeIsIt
  author <- assumingBasicUser
  doc <- assumingBasicContract mt author
  --execute
  let sd = signatoryDetailsFromUser author
  enewdoc <- update $ UpdateDocument mt (documentid doc) "New Title" [] Nothing "" (sd, [SignatoryAuthor, SignatoryPartner], (userid author, Nothing)) [EmailIdentification] Nothing AdvancedFunctionality 
  --assert
  case enewdoc of
    Left msg -> assertFailure $ "Could not run UpdateDocument: " ++ msg
    Right newdoc -> assertEqual "document name should be different" (documenttitle newdoc) "New Title"
    
testDocumentAttachAlwaysRight :: Assertion
testDocumentAttachAlwaysRight = do
  -- setup
  mt <- whatTimeIsIt
  author <- assumingBasicUser
  doc <- assumingBasicContract mt author
  --execute
  edoc <- update $ AttachFile (documentid doc) "some file" "some content"
  --assert
  case edoc of
    Left msg -> assertFailure $ "Could not run AttachFile: " ++ msg
    Right _newdoc -> assertSuccess

testNoDocumentAttachAlwaysLeft :: Assertion
testNoDocumentAttachAlwaysLeft = do
  -- setup
  --execute
  -- non-existent docid
  edoc <- update $ AttachFile (DocumentID 4) "some file" "some content"
  --assert
  case edoc of
    Left _msg     -> assertSuccess
    Right _newdoc -> assertFailure "Should not succeed if no document"

testDocumentAttachHasAttachment :: Assertion
testDocumentAttachHasAttachment = do
  -- setup
  mt <- whatTimeIsIt
  author <- assumingBasicUser
  doc <- assumingBasicContract mt author
  let fname = "some file" :: BS.ByteString
      content  = "some content" :: BS.ByteString
  --execute
  edoc <- update $ AttachFile (documentid doc) fname content
  --assert
  case edoc of
    Left msg -> assertFailure $ "Could not run AttachFile: " ++ msg
    Right newdoc -> case find ((== fname) . filename) (documentfiles newdoc) of
      Just _ -> assertSuccess
      _ -> assertFailure "File does exist or wrong name"

apply :: a -> (a -> b) -> b
apply a f = f a

assertInvariants :: Document -> Assertion
assertInvariants document =
  case catMaybes $ map (apply document) documentInvariants of
    [] -> assertSuccess
    a  -> assertFailure $ (show $ documentid document) ++ ": " ++ intercalate ";" a

documentInvariants :: [Document -> Maybe String]
documentInvariants = [
  documentHasOneAuthor
                     ]

{- |
   Test the invariant that a document must have exactly one author.
-}
documentHasOneAuthor :: Document -> Maybe String
documentHasOneAuthor document =
  case filter isAuthor $ documentsignatorylinks document of
    [_] -> Nothing
    a -> Just $ "document must have one author (has " ++ show (length a) ++ ")"

assertSuccess :: Assertion
assertSuccess = assertBool "not success?!" True

_addNewUserWithSupervisor :: Int -> String -> String -> String -> IO (Maybe User)
_addNewUserWithSupervisor superid = addNewUser' (Just superid)

addNewUser :: String -> String -> String -> IO (Maybe User)
addNewUser = addNewUser' Nothing

addNewUser' :: Maybe Int -> String -> String -> String -> IO (Maybe User)
addNewUser' msuperid firstname secondname email = do
  muser <- update $ AddUser (BS.fromString firstname, BS.fromString secondname) (BS.fromString email) NoPassword (fmap UserID msuperid) Nothing Nothing
  return muser

whatTimeIsIt :: IO (MinutesTime)
whatTimeIsIt = liftIO $ getMinutesTime

assumingBasicContract :: MinutesTime -> User -> IO (Document)
assumingBasicContract mt author = do
  doc <- update $ NewDocument author "Test Document" (Signable Contract) mt
  mdoc <- query $ GetDocumentByDocumentID (documentid doc)
  case mdoc of
    Nothing -> do
      assertFailure "Could not create + store document."
      return blankDocument
    Just d -> return d


assumingBasicUser :: IO (User)
assumingBasicUser = do
  muser <- addNewUser "Eric" "Normand" "eric@fds.com"
  case muser of
    Just user -> return user
    Nothing -> do
      assertFailure "Cannot create a new user (in setup)"
      return blankUser -- should not be possible

blankUser :: User
blankUser = User {  
                   userid                  =  UserID 0
                 , userpassword            =  NoPassword
                 , usersupervisor          =  Nothing 
                 , useraccountsuspended    =  False  
                 , userhasacceptedtermsofservice = Nothing
                 , userfreetrialexpirationdate = Nothing
                 , usersignupmethod = AccountRequest
                 , userinfo = UserInfo {
                                    userfstname = BS.empty
                                  , usersndname = BS.empty
                                  , userpersonalnumber = BS.empty
                                  , usercompanyname =  BS.empty
                                  , usercompanyposition =  BS.empty
                                  , usercompanynumber  =  BS.empty
                                  , useraddress =  BS.empty
                                  , userzip = BS.empty
                                  , usercity  = BS.empty
                                  , usercountry = BS.empty
                                  , userphone = BS.empty
                                  , usermobile = BS.empty
                                  , useremail =  Email BS.empty 
                                   }
                , usersettings  = UserSettings {
                                    accounttype = PrivateAccount
                                  , accountplan = Basic
                                  , signeddocstorage = Nothing
                                  , userpaymentmethod = Undefined
                                  , preferreddesignmode = Nothing
                                  , lang = Misc.defaultValue
                                  }                   
                , userpaymentpolicy = Payments.initialPaymentPolicy
                , userpaymentaccount = Payments.emptyPaymentAccount
              , userfriends = []
              , userinviteinfo = Nothing
              , userlogininfo = LoginInfo
                                { lastsuccesstime = Nothing
                                , lastfailtime = Nothing
                                , consecutivefails = 0
                                }
              , userservice = Nothing
              , usercompany = Nothing
              , usermailapi = Nothing
              , userrecordstatus = LiveUser
              }

blankDocument :: Document 
blankDocument =
          Document
          { documentid                   = DocumentID 0
          , documenttitle                = BS.empty
          , documentsignatorylinks       = []
          , documentfiles                = []
          , documentstatus               = Preparation
          , documenttype                 = Signable Contract
          , documentfunctionality        = BasicFunctionality
          , documentctime                = fromSeconds 0
          , documentmtime                = fromSeconds 0
          , documentdaystosign           = Nothing
          , documenttimeouttime          = Nothing
          , documentlog                  = []
          , documentinvitetext           = BS.empty
          , documentsealedfiles          = []
          , documenttrustweaverreference = Nothing
          , documentallowedidtypes       = []
          , documentcsvupload            = Nothing
          , documentcancelationreason    = Nothing
          , documentinvitetime           = Nothing
          , documentsharing              = Doc.DocState.Private
          , documentrejectioninfo        = Nothing
          , documenttags                 = []
          , documentui                   = emptyDocumentUI
          , documentservice              = Nothing
          , documentauthorattachments    = []
          , documentoriginalcompany      = Nothing
          , documentrecordstatus         = LiveDocument
          , documentquarantineexpiry     = Nothing
          , documentsignatoryattachments = []
          , documentattachments          = []
          }
