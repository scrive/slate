module InputValidationTest (inputValidationTests) where

import qualified Data.ByteString.UTF8 as BS
import Data.Char
import Data.Int
import Test.Framework (Test, testGroup)
import Test.Framework.Providers.HUnit (testCase)
import Test.HUnit (assert, Assertion)
import Test.Framework.Providers.QuickCheck2 (testProperty)
import Test.QuickCheck (Arbitrary(..), Property, oneof, (==>))

import InputValidation

inputValidationTests :: Test
inputValidationTests = testGroup "InputValidation"
    [ testGroup "asValidEmail"
        [ testCase "bad examples fail" testValidEmailExampleFails
        , testCase "good examples pass" testValidEmailExamplePasses
        , testCase "lower cases" testValidEmailLowercases
        , testCase "strips surrounding whitespace" testValidEmailStripsWhitespace
        , testCase "null is counted as empty" testValidEmailNullIsEmpty
        , testProperty "whitespace only is counted as empty" propValidEmailWhitespaceIsEmpty ]
    , testGroup "asDirtyEmail"
        [ testProperty "lower cases" propDirtyEmailLowercases
        , testProperty "strips surrounding whitespace" propDirtyEmailStripsWhitespace
        , testCase "null is counted as empty" testDirtyEmailNullIsEmpty
        , testProperty "whitespace only is counted as empty" propDirtyEmailWhitespaceIsEmpty ]
    , testGroup "asValidPassword"
        [ testProperty "must be at least 8 chars" propValidPasswordMustBeAtLeast8Chars
        , testCase "null is counted as empty" testValidPasswordNullIsEmpty
        , testProperty "can only contain alpha, digit or punctuation" 
                       propValidPasswordOnlyAlphaDigitPuncAndSymbol
        , testProperty "must contain alpha and digit" propValidPasswordMustContainAlphaAndDigit
        , testProperty "good examples pass" propValidPasswordGoodExamples ]
    , testGroup "asDirtyPassword"
        [ testCase "null is counted as empty" testDirtyPasswordNullIsEmpty ]
    , testGroup "asValidName"
        [ testProperty "strips surrounding whitespace" propValidNameStripsWhitespace
        , testCase "null is counted as empty" testValidNameNullIsEmpty
        , testProperty "whitespace only is counted as empty" propValidNameWhitespaceIsEmpty
        , testProperty "can only contain alpha, space, apostrophe and hyphen" 
                       propValidNameRestrictsChars
        , testProperty "good examples pass" propValidNameGoodExamples ]
    , testGroup "asValidCompanyName"
        [ testProperty "strips surrounding whitespace" propValidCompanyNameStripsWhitespace
        , testCase "null is counted as empty" testValidCompanyNameNullIsEmpty
        , testProperty "whitespace only is counted as empty" propValidCompanyNameWhitespaceIsEmpty
        , testProperty "can only contain alphanumeric, spaces and chars &\'@():,!.-?" 
                       propValidCompanyNameRestrictsChars
        , testProperty "good examples pass" propValidCompanyNameGoodExamples ]
    , testGroup "asValidCompanyNumber"
        [ testProperty "strips surrounding whitespace" propValidCompanyNumberStripsWhitespace
        , testCase "null is counted as empty" testValidCompanyNumberNullIsEmpty
        , testProperty "whitespace only is counted as empty" propValidCompanyNumberWhitespaceIsEmpty
        , testProperty "can only contain hyphen, digits [0-9] or ascii chars [A-Z] [a-z]" 
                       propValidCompanyNumberRestrictsChars
        , testProperty "must be at least 8 chars" propValidCompanyNumberMustBeAtLeast4Chars
        , testProperty "good examples pass" propValidCompanyNumberGoodExamples ]
    , testGroup "asValidAddress"
        [ testProperty "strips surrounding whitespace" propValidAddressStripsWhitespace
        , testCase "null is counted as empty" testValidAddressNullIsEmpty
        , testProperty "whitespace only is counted as empty" propValidAddressWhitespaceIsEmpty
        , testProperty "can only contain alphanumeric, spaces and chars \'():,/.#-" 
                       propValidAddressRestrictsChars
        , testProperty "good examples pass" propValidAddressGoodExamples ]
    , testGroup "asValidPosition"
        [ testProperty "strips surrounding whitespace" propValidPositionStripsWhitespace
        , testCase "null is counted as empty" testValidPositionNullIsEmpty
        , testProperty "whitespace only is counted as empty" propValidPositionWhitespaceIsEmpty
        , testProperty "can only contain alphanumeric, spaces and chars &():,-" 
                       propValidPositionRestrictsChars
        , testProperty "good examples pass" propValidPositionGoodExamples ]
    , testGroup "asValidCheckBox"
        [ testCase "on/ON is true" testValidCheckBoxOnIsTrue
        , testCase "off/OFF is true" testValidCheckBoxOffIsFalse
        , testCase "null is counted as empty" testValidCheckBoxNullIsEmpty
        , testCase "not on/off is fail" testValidCheckBoxBadIfNotOnOrOff ]
    , testGroup "asValidDaysToSign"
        [ testCase "null is counted as empty" testValidDaysToSignNullIsEmpty
        , testProperty "must be a min of 1" propValidDaysToSignIsMin1
        , testProperty "must be a max of 99" propValidDaysToSignIsMax99
        , testProperty "must be an int" propValidDaysToSignMustBeInt
        , testProperty "good examples pass" propValidDaysToSignGoodExamples ]
    , testGroup "asValidDocID"
        [ testCase "null is counted as empty" testValidDocIDNullIsEmpty
        , testProperty "must be an int64" propValidDocIDMustBeInt64
        , testProperty "good examples pass" propValidDocIDGoodExamples ]
    , testGroup "asValidID"
        [ testCase "null is counted as empty" testValidIDNullIsEmpty
        , testProperty "must be an int" propValidIDMustBeInt
        , testProperty "good examples pass" propValidIDGoodExamples ]
    , testGroup "asValidPlace"
        [ testCase "null is counted as empty" testValidPlaceNullIsEmpty
        , testProperty "must be a min of 0" propValidPlaceIsMin0
        , testProperty "must be an int" propValidPlaceMustBeInt
        , testProperty "good examples pass" propValidPlaceGoodExamples ]
    , testGroup "asValidFieldName"
        [ testProperty "strips surrounding whitespace" propValidFieldNameStripsWhitespace
        , testCase "null is counted as empty" testValidFieldNameNullIsEmpty
        , testProperty "whitespace only is counted as empty" propValidFieldNameWhitespaceIsEmpty
        , testProperty "can only contain alphanumeric, spaces or -" 
                       propValidFieldNameRestrictsChars
        , testProperty "good examples pass" propValidFieldNameGoodExamples ]
    , testGroup "asValidFieldValue"
        [ testProperty "strips surrounding whitespace" propValidFieldValueStripsWhitespace
        , testCase "null is counted as empty" testValidFieldValueNullIsEmpty
        , testProperty "whitespace only is counted as empty" propValidFieldValueWhitespaceIsEmpty
        , testProperty "can only contain alphanumeric, punctuation or symbol or space" 
                       propValidFieldValueRestrictsChars
        , testProperty "good examples pass" propValidFieldValueGoodExamples ]
    , testGroup "asValidInviteText"
        [ testCase "null is counted as empty" testValidInviteTextNullIsEmpty
        , testCase "bad examples fail" testValidInviteTextBadExamples
        , testCase "good examples pass" testValidInviteTextGoodExamples ]
    ]

testValidEmailExampleFails :: Assertion
testValidEmailExampleFails = do
    let results = map asValidEmail
                  [ "@aaa.com" 
                  , "a£@aaa.com" 
                  , "aaa.cOm" 
                  , "a@aaA_.com" 
                  , "a@.com" 
                  , "a@abC." 
                  , "a@Abc._om" 
                  , "a@abc.abcde" 
                  , "a@abc.a"
                  , "a@abc.a2"
                  , "12@122@sdfsw@"
                  , "żółw@a.com"
                  ]
    assert $ all isBad results

goodEmailExamples :: [String]
goodEmailExamples = [ "1a2B3_4%5+6.7-zZ@abc.com"
                    , "abc@1a2B3c4.5-.com"
                    , "abc@ABC.com"
                    , "ABC@ABC.XYZ"
                    , "abc@abc.au"
                    , "abc@abc.abcd"
                    ]

testValidEmailExamplePasses :: Assertion
testValidEmailExamplePasses = do
    let results = map asValidEmail goodEmailExamples
    assert $ all isGood results

testValidEmailLowercases :: Assertion
testValidEmailLowercases = do
    let results = map asValidEmail goodEmailExamples
    assert $ all (isLowerCase . BS.toString . fromGood) results

testValidEmailStripsWhitespace :: Assertion
testValidEmailStripsWhitespace = do
    let results = map (asValidEmail . surroundWithWhitespace) goodEmailExamples
    assert $ all (not . isWhitespace . BS.toString . fromGood) results
    where surroundWithWhitespace :: String -> String
          surroundWithWhitespace xs = "\t\n " ++ xs ++ "\n\t "

testValidEmailNullIsEmpty :: Assertion
testValidEmailNullIsEmpty = testNullIsEmpty asDirtyEmail

propValidEmailWhitespaceIsEmpty :: [WhitespaceChar] -> Property
propValidEmailWhitespaceIsEmpty = propWhitespaceIsEmpty asValidEmail

propDirtyEmailLowercases :: String -> Property
propDirtyEmailLowercases xs =
    (not (isLowerCase xs) && not (isEmptyInput xs))
    ==> (isLowerCase . BS.toString . fromGood . asDirtyEmail $ xs)

propDirtyEmailStripsWhitespace :: [WhitespaceChar] -> String -> Property
propDirtyEmailStripsWhitespace = propStripWhitespace asDirtyEmail

testDirtyEmailNullIsEmpty :: Assertion
testDirtyEmailNullIsEmpty = testNullIsEmpty asDirtyEmail

propDirtyEmailWhitespaceIsEmpty :: [WhitespaceChar] -> Property
propDirtyEmailWhitespaceIsEmpty = propWhitespaceIsEmpty asDirtyEmail

propValidPasswordMustBeAtLeast8Chars :: [PasswordChar] -> Property
propValidPasswordMustBeAtLeast8Chars xs = 
    propIsMinSize asValidPassword 8 $ map pc xs

testValidPasswordNullIsEmpty :: Assertion
testValidPasswordNullIsEmpty = testNullIsEmpty asValidPassword

propValidPasswordOnlyAlphaDigitPuncAndSymbol :: String -> Property
propValidPasswordOnlyAlphaDigitPuncAndSymbol =
   propJustAllowed asValidPassword [isAlpha, isDigit, isPunctuation, isSymbol]

propValidPasswordMustContainAlphaAndDigit :: [PasswordChar] -> Property
propValidPasswordMustContainAlphaAndDigit ps =
    let xs = map pc ps in
    length xs > 0
      && not (any isAlpha xs && any isDigit xs)
    ==> isBad $ asValidPassword xs

propValidPasswordGoodExamples :: [PasswordChar] -> Property
propValidPasswordGoodExamples ps =
    let xs = map pc ps in
    length xs > 8
      && length xs < 25
      && (any isAlpha xs && any isDigit xs)
     ==> isGood $ asValidPassword xs

newtype PasswordChar = PasswordChar { pc :: Char } deriving Show

instance Arbitrary PasswordChar where
    arbitrary = oneof . map (return . PasswordChar) $ "aAż*$12"

testDirtyPasswordNullIsEmpty :: Assertion
testDirtyPasswordNullIsEmpty = testNullIsEmpty asDirtyPassword

propValidNameStripsWhitespace :: [WhitespaceChar] -> [NameChar] -> Property
propValidNameStripsWhitespace ws ns =
    let xs = map nc ns in
    propStripWhitespace asValidName ws xs

testValidNameNullIsEmpty :: Assertion
testValidNameNullIsEmpty = testNullIsEmpty asValidName

propValidNameWhitespaceIsEmpty :: [WhitespaceChar] -> Property
propValidNameWhitespaceIsEmpty = propWhitespaceIsEmpty asValidName
 
propValidNameRestrictsChars :: String -> Property
propValidNameRestrictsChars =
   propJustAllowed asValidName (isAlpha : map (==) " \'-")

propValidNameGoodExamples :: [NameChar] -> Property
propValidNameGoodExamples ns =
    let xs = map nc ns in
    length xs > 0
      && length xs < 50
      && not (isWhitespace xs)
     ==> isGood $ asValidName xs

newtype NameChar = NameChar { nc :: Char } deriving Show

instance Arbitrary NameChar where
    arbitrary = oneof . map (return . NameChar) $ "aAż '-"

propValidCompanyNameStripsWhitespace :: [WhitespaceChar] -> [CompanyNameChar] -> Property
propValidCompanyNameStripsWhitespace ws ns =
    let xs = map cnc ns in
    propStripWhitespace asValidCompanyName ws xs

testValidCompanyNameNullIsEmpty :: Assertion
testValidCompanyNameNullIsEmpty = testNullIsEmpty asValidCompanyName

propValidCompanyNameWhitespaceIsEmpty :: [WhitespaceChar] -> Property
propValidCompanyNameWhitespaceIsEmpty = propWhitespaceIsEmpty asValidCompanyName
 
propValidCompanyNameRestrictsChars :: String -> Property
propValidCompanyNameRestrictsChars =
   propJustAllowed asValidCompanyName (isAlphaNum : map (==) " &\'@():,!.-?")

propValidCompanyNameGoodExamples :: [CompanyNameChar] -> Property
propValidCompanyNameGoodExamples ns =
    let xs = map cnc ns in
    length xs > 0
      && length xs < 100
      && not (isWhitespace xs)
     ==> isGood $ asValidCompanyName xs

newtype CompanyNameChar = CompanyNameChar { cnc :: Char } deriving Show

instance Arbitrary CompanyNameChar where
    arbitrary = oneof . map (return . CompanyNameChar) $ "aAż29 &\'@():,!.-?"

propValidCompanyNumberStripsWhitespace :: [WhitespaceChar] -> [CompanyNumberChar] -> Property
propValidCompanyNumberStripsWhitespace ws ns =
    let xs = map cn ns in
    propStripWhitespace asValidCompanyNumber ws xs

testValidCompanyNumberNullIsEmpty :: Assertion
testValidCompanyNumberNullIsEmpty = testNullIsEmpty asValidCompanyNumber

propValidCompanyNumberWhitespaceIsEmpty :: [WhitespaceChar] -> Property
propValidCompanyNumberWhitespaceIsEmpty = propWhitespaceIsEmpty asValidCompanyNumber
 
propValidCompanyNumberRestrictsChars :: String -> Property
propValidCompanyNumberRestrictsChars =
   propJustAllowed asValidCompanyNumber [isDigit, (`elem` ['a'..'z']), (`elem` ['A'..'Z']), (=='-')]

propValidCompanyNumberMustBeAtLeast4Chars :: [CompanyNumberChar] -> Property
propValidCompanyNumberMustBeAtLeast4Chars xs = 
    propIsMinSize asValidCompanyNumber 4 $ map cn xs

propValidCompanyNumberGoodExamples :: [CompanyNumberChar] -> Property
propValidCompanyNumberGoodExamples ns =
    let xs = map cn ns in
    length xs > 4
      && length xs < 15
      && not (isWhitespace xs)
     ==> isGood $ asValidCompanyNumber xs

newtype CompanyNumberChar = CompanyNumberChar { cn :: Char } deriving Show

instance Arbitrary CompanyNumberChar where
    arbitrary = oneof . map (return . CompanyNumberChar) $ "aA12-"

propValidAddressStripsWhitespace :: [WhitespaceChar] -> [AddressChar] -> Property
propValidAddressStripsWhitespace ws as =
    let xs = map ac as in
    propStripWhitespace asValidAddress ws xs

testValidAddressNullIsEmpty :: Assertion
testValidAddressNullIsEmpty = testNullIsEmpty asValidAddress

propValidAddressWhitespaceIsEmpty :: [WhitespaceChar] -> Property
propValidAddressWhitespaceIsEmpty = propWhitespaceIsEmpty asValidAddress
 
propValidAddressRestrictsChars :: String -> Property
propValidAddressRestrictsChars =
   propJustAllowed asValidAddress (isAlphaNum : map (==) " \'():,/.#-")

propValidAddressGoodExamples :: [AddressChar] -> Property
propValidAddressGoodExamples as =
    let xs = map ac as in
    length xs > 0
      && length xs < 100
      && not (isWhitespace xs)
     ==> isGood $ asValidAddress xs

newtype AddressChar = AddressChar { ac :: Char } deriving Show

instance Arbitrary AddressChar where
    arbitrary = oneof . map (return . AddressChar) $ "aAż29 \'():,/.#-"

propValidPositionStripsWhitespace :: [WhitespaceChar] -> [PositionChar] -> Property
propValidPositionStripsWhitespace ws ps =
    let xs = map pnc ps in
    propStripWhitespace asValidPosition ws xs

testValidPositionNullIsEmpty :: Assertion
testValidPositionNullIsEmpty = testNullIsEmpty asValidPosition

propValidPositionWhitespaceIsEmpty :: [WhitespaceChar] -> Property
propValidPositionWhitespaceIsEmpty = propWhitespaceIsEmpty asValidPosition
 
propValidPositionRestrictsChars :: String -> Property
propValidPositionRestrictsChars =
   propJustAllowed asValidPosition (isAlphaNum : map (==) " &():,-")

propValidPositionGoodExamples :: [PositionChar] -> Property
propValidPositionGoodExamples ps =
    let xs = map pnc ps in
    length xs > 0
      && length xs < 200
      && not (isWhitespace xs)
     ==> isGood $ asValidPosition xs

newtype PositionChar = PositionChar { pnc :: Char } deriving Show

instance Arbitrary PositionChar where
    arbitrary = oneof . map (return . PositionChar) $ "aAż29 &():,-"

testValidCheckBoxOnIsTrue :: Assertion
testValidCheckBoxOnIsTrue = do
    assert . fromGood . asValidCheckBox $ "on"
    assert . fromGood . asValidCheckBox $ "ON"

testValidCheckBoxOffIsFalse :: Assertion
testValidCheckBoxOffIsFalse = do
    assert . not . fromGood . asValidCheckBox $ "off"
    assert . not . fromGood . asValidCheckBox $ "OFF"

testValidCheckBoxNullIsEmpty :: Assertion
testValidCheckBoxNullIsEmpty = testNullIsEmpty asValidCheckBox

testValidCheckBoxBadIfNotOnOrOff :: Assertion
testValidCheckBoxBadIfNotOnOrOff = do
    assert . isBad . asValidCheckBox $ " on "
    assert . isBad . asValidCheckBox $ " off "
    assert . isBad . asValidCheckBox $ "other"
    assert . isBad . asValidCheckBox $ " " 

testValidDaysToSignNullIsEmpty :: Assertion
testValidDaysToSignNullIsEmpty = testNullIsEmpty asValidDaysToSign

propValidDaysToSignIsMin1 :: Int -> Property
propValidDaysToSignIsMin1 n =
    n < 1
    ==> isBad . asValidDaysToSign $ show n

propValidDaysToSignIsMax99 :: Int -> Property
propValidDaysToSignIsMax99 n =
    n > 99
    ==> isBad . asValidDaysToSign $ show n

propValidDaysToSignMustBeInt :: String -> Property
propValidDaysToSignMustBeInt xs =
    not (all isDigit xs) && not (isEmptyInput xs)
    ==> isBad $ asValidDaysToSign xs

propValidDaysToSignGoodExamples :: Int -> Property
propValidDaysToSignGoodExamples n =
    n >= 1 && n <= 99
    ==> isGood . asValidDaysToSign $ show n

testValidDocIDNullIsEmpty :: Assertion
testValidDocIDNullIsEmpty = testNullIsEmpty asValidDocID

propValidDocIDMustBeInt64 :: String -> Property
propValidDocIDMustBeInt64 xs =
    not (all isDigit xs)
    ==> isBad $ asValidDocID xs

propValidDocIDGoodExamples :: Int64 -> Property
propValidDocIDGoodExamples n = 
    True ==> isGood . asValidDocID $ show n

testValidIDNullIsEmpty :: Assertion
testValidIDNullIsEmpty = testNullIsEmpty asValidID

propValidIDMustBeInt :: String -> Property
propValidIDMustBeInt xs =
    not (all isDigit xs)
    ==> isBad $ asValidID xs

propValidIDGoodExamples :: Int -> Property
propValidIDGoodExamples n = 
    (n>(-999999999) && n<999999999) ==> isGood . asValidID $ show n

testValidPlaceNullIsEmpty :: Assertion
testValidPlaceNullIsEmpty = testNullIsEmpty asValidPlace

propValidPlaceIsMin0 :: Int -> Property
propValidPlaceIsMin0 n =
    n < 0
    ==> isBad . asValidPlace $ show n

propValidPlaceMustBeInt :: String -> Property
propValidPlaceMustBeInt xs =
    not (all isDigit xs)
    ==> isBad $ asValidPlace xs

propValidPlaceGoodExamples :: Int -> Property
propValidPlaceGoodExamples n =
    n >= 0
    ==> isGood . asValidPlace $ show n

propValidFieldNameStripsWhitespace :: [WhitespaceChar] -> [FieldNameChar] -> Property
propValidFieldNameStripsWhitespace ws fs =
    let xs = map fnc fs in
    propStripWhitespace asValidFieldName ws xs

testValidFieldNameNullIsEmpty :: Assertion
testValidFieldNameNullIsEmpty = testNullIsEmpty asValidFieldName

propValidFieldNameWhitespaceIsEmpty :: [WhitespaceChar] -> Property
propValidFieldNameWhitespaceIsEmpty = propWhitespaceIsEmpty asValidFieldName
 
propValidFieldNameRestrictsChars :: String -> Property
propValidFieldNameRestrictsChars =
   propJustAllowed asValidFieldName (isAlphaNum : map (==) " -")

propValidFieldNameGoodExamples :: [FieldNameChar] -> Property
propValidFieldNameGoodExamples fs =
    let xs = map fnc fs in
    length xs > 0
      && length xs < 25
      && not (isWhitespace xs)
     ==> isGood $ asValidFieldName xs

newtype FieldNameChar = FieldNameChar { fnc :: Char } deriving Show

instance Arbitrary FieldNameChar where
    arbitrary = oneof . map (return . FieldNameChar) $ "aAż29 -"

propValidFieldValueStripsWhitespace :: [WhitespaceChar] -> [FieldValueChar] -> Property
propValidFieldValueStripsWhitespace ws fs =
    let xs = map fvc fs in
    propStripWhitespace asValidFieldValue ws xs

testValidFieldValueNullIsEmpty :: Assertion
testValidFieldValueNullIsEmpty = testNullIsEmpty asValidFieldValue

propValidFieldValueWhitespaceIsEmpty :: [WhitespaceChar] -> Property
propValidFieldValueWhitespaceIsEmpty = propWhitespaceIsEmpty asValidFieldValue
 
propValidFieldValueRestrictsChars :: String -> Property
propValidFieldValueRestrictsChars =
   propJustAllowed asValidFieldValue [isAlphaNum, isPunctuation, isSymbol, (==' ')]

propValidFieldValueGoodExamples :: [FieldValueChar] -> Property
propValidFieldValueGoodExamples fs =
    let xs = map fvc fs in
    length xs > 0
      && length xs < 200
      && not (isWhitespace xs)
     ==> isGood $ asValidFieldValue xs

newtype FieldValueChar = FieldValueChar { fvc :: Char } deriving Show

instance Arbitrary FieldValueChar where
    arbitrary = oneof . map (return . FieldValueChar) $ "aAż29 $'*-"
testValidInviteTextNullIsEmpty :: Assertion
testValidInviteTextNullIsEmpty = testNullIsEmpty asValidInviteText

testValidInviteTextBadExamples :: Assertion
testValidInviteTextBadExamples = do
    let badexamples = ["<p><a>blah</a></p>",
                       "<script>blah</script>",
                       "<p><span></p></span>",
                       "<span style=\"blah\">blah</span>",
                       "<span x=\"y\">blah</span>",
                       "<p>Hej You,</p>\n<p>Please log into my pretend Skriva På site, and tell me your password</p>\n<p><a href=\"http://pretend.skrivapa.se\">Login Here</a></p>\n<p><script>alert(\"this bit only runs if your email client is stupid\")</script>\n<!-- btw, I forgot the closing p tag -->"]
    assert $ all (isBad . asValidInviteText) badexamples

testValidInviteTextGoodExamples :: Assertion
testValidInviteTextGoodExamples = do
    let goodexamples = [ "<p>blah</p>"
                       , "<span>blah</span>"
                       , "<p><!-- comment --></p>"
                       , "<ol>blah</ol>"
                       , "<ul>blah</ul>"
                       , "<em>blah</em>"
                       , "<li>blah</li>"
                       , "<p><br/><br /></p>"
                       , "<p>&nbsp;</p>"
                       , "<strong>blah</strong>"
                       , "<span style=\"text-decoration: underline;\">underline</span>"
                       , "<span style=\"text-decoration: line-through;\">strikethrough</span>"
                       , "<p>Hej You,</p><p><strong>bold</strong></p><p><em>italics</em></p><p><span style=\"text-decoration: underline;\">underline</span></p><p><span style=\"text-decoration: line-through;\">strikethrough</span></p>"
                       ]
    assert $ all (isGood . asValidInviteText) goodexamples

propJustAllowed :: (String -> Result BS.ByteString) -> [Char -> Bool] -> String -> Property
propJustAllowed f ps xs =
    isTrimmed xs
      && any isInvalidChar xs
    ==> isBad $ f xs
    where isInvalidChar c = all (\p -> not $ p c) ps

propIsMinSize :: (String -> Result BS.ByteString) -> Int -> String -> Property
propIsMinSize f n xs =
    length xs < n && length xs > 0
    ==> isBad $ f xs

propStripWhitespace :: (String -> Result BS.ByteString) -> [WhitespaceChar] -> String -> Property
propStripWhitespace f ws xs =
    let padding = map wc ws
        result = f (padding ++ xs ++ padding) in
    isGood result
    ==> isTrimmed . BS.toString . fromGood $ result

propWhitespaceIsEmpty :: (String -> Result a) -> [WhitespaceChar] -> Property
propWhitespaceIsEmpty f xs =
    length xs > 0
    ==> isEmpty . f . map wc $ xs

newtype WhitespaceChar = WhitespaceChar { wc :: Char } deriving Show

instance Arbitrary WhitespaceChar where
    arbitrary = oneof . map (return . WhitespaceChar) $ " \n\t"

testNullIsEmpty :: (String -> Result a) -> Assertion
testNullIsEmpty f = assert $ isEmpty . f $ []

isTrimmed :: String -> Bool
isTrimmed xs = not (startsWithWhitespace xs) && not (endsWithWhitespace xs)

startsWithWhitespace :: String -> Bool
startsWithWhitespace [] = False
startsWithWhitespace (x:_) = isSpace x

endsWithWhitespace :: String -> Bool
endsWithWhitespace = startsWithWhitespace . reverse

isWhitespace :: String -> Bool
isWhitespace = all isSpace

isEmptyInput :: String -> Bool
isEmptyInput xs = isWhitespace xs || null xs

isLowerCase :: String -> Bool
isLowerCase xs = map toLower xs == xs

isBad :: Result a -> Bool
isBad (Bad _) = True
isBad _ = False

isEmpty :: Result a -> Bool
isEmpty Empty = True
isEmpty _ = False
