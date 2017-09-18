{-# OPTIONS_GHC -fno-warn-orphans #-}
module Doc.API.V2.JSON.Fields (
  unjsonSignatoryFields
, unjsonSignatoryFieldsValuesForSigning
, SignatoryFieldsValuesForSigning(..)
, SignatoryFieldTMPValue(..)
) where

import Control.Applicative.Free
import Data.Functor.Invariant
import Data.String.Utils
import Data.Text.Encoding
import Data.Unjson
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Char8 as BS
import qualified Data.Text as T

import Doc.API.V2.JSON.Misc ()
import Doc.API.V2.JSON.Utils
import Doc.Data.CheckboxPlacementsUtils
import Doc.Data.RadiobuttonPlacementsUtils
import Doc.DocStateData
import Doc.SignatoryFieldID
import KontraPrelude
import qualified Data.ByteString.RFC2397 as RFC2397

-- Unjson for signatory fields
unjsonSignatoryFields :: UnjsonDef [SignatoryField]
unjsonSignatoryFields = arrayOf unjsonSignatoryField

unjsonSignatoryField :: UnjsonDef SignatoryField
unjsonSignatoryField = DisjointUnjsonDef "type" [
    (fieldTypeToText NameFT, (\f -> fieldType f == NameFT), (return . SignatoryNameField <$> unjsonNameField))
  , (fieldTypeToText CompanyFT, (\f -> fieldType f == CompanyFT), (return . SignatoryCompanyField <$> unjsonCompanyField))
  , (fieldTypeToText PersonalNumberFT, (\f -> fieldType f == PersonalNumberFT), (return . SignatoryPersonalNumberField <$> unjsonPersonalNumberField))
  , (fieldTypeToText CompanyNumberFT, (\f -> fieldType f == CompanyNumberFT), (return . SignatoryCompanyNumberField <$> unjsonCompanyNumberField))
  , (fieldTypeToText EmailFT, (\f -> fieldType f == EmailFT), (return . SignatoryEmailField <$> unjsonEmailField))
  , (fieldTypeToText MobileFT, (\f -> fieldType f == MobileFT), (return . SignatoryMobileField <$> unjsonMobileField))
  , (fieldTypeToText TextFT, (\f -> fieldType f == TextFT), (return . SignatoryTextField <$> unjsonTextField))
  , (fieldTypeToText CheckboxFT, (\f -> fieldType f == CheckboxFT), (return . SignatoryCheckboxField <$> unjsonCheckboxField))
  , (fieldTypeToText SignatureFT, (\f -> fieldType f == SignatureFT), (return . SignatorySignatureField <$> unjsonSignatureField))
  , (fieldTypeToText RadioGroupFT, (\f -> fieldType f == RadioGroupFT), (fmap SignatoryRadioGroupField <$> unjsonRadioGroupField))
  ]


unjsonNameField :: Ap (FieldDef SignatoryField) SignatoryNameField
unjsonNameField = pure (\no v ob sfbs ps -> NameField (unsafeSignatoryFieldID 0) no v ob sfbs ps)
  <*> field "order" (unsafeFromNameField snfNameOrder) "Order of name field"
  <*> fieldDef "value" "" (unsafeFromNameField snfValue) "Value of the field"
  <*> fieldDef "is_obligatory" True (unsafeFromNameField snfObligatory) "If is oligatory"
  <*> fieldDef "should_be_filled_by_sender" False (unsafeFromNameField snfShouldBeFilledBySender) "If should be filled by sender"
  <*> fieldDefBy "placements" [] (unsafeFromNameField snfPlacements) "Placements" (arrayOf unsonFieldPlacement)
  where
    unsafeFromNameField :: (SignatoryNameField -> a) -> SignatoryField -> a
    unsafeFromNameField f (SignatoryNameField a) = f a
    unsafeFromNameField _ _ = $unexpectedError "unsafeFromNameField"

unjsonCompanyField :: Ap (FieldDef SignatoryField) SignatoryCompanyField
unjsonCompanyField = pure (\v ob sfbs ps -> CompanyField (unsafeSignatoryFieldID 0) v ob sfbs ps)
  <*> fieldDef "value" "" (unsafeFromCompanyField scfValue) "Value of the field"
  <*> fieldDef "is_obligatory" True (unsafeFromCompanyField scfObligatory) "If is oligatory"
  <*> fieldDef "should_be_filled_by_sender" False (unsafeFromCompanyField scfShouldBeFilledBySender) "If should be filled by sender"
  <*> fieldDefBy "placements" [] (unsafeFromCompanyField scfPlacements) "Placements" (arrayOf unsonFieldPlacement)
  where
    unsafeFromCompanyField :: (SignatoryCompanyField -> a) -> SignatoryField -> a
    unsafeFromCompanyField f (SignatoryCompanyField a) = f a
    unsafeFromCompanyField _ _ = $unexpectedError "unsafeFromCompanyField"

unjsonPersonalNumberField :: Ap (FieldDef SignatoryField) SignatoryPersonalNumberField
unjsonPersonalNumberField = pure (\v ob sfbs ps-> PersonalNumberField (unsafeSignatoryFieldID 0) (strip v) ob sfbs ps)
  <*> fieldDef "value" "" (unsafeFromPersonalNumberField spnfValue) "Value of the field"
  <*> fieldDef "is_obligatory" True (unsafeFromPersonalNumberField spnfObligatory) "If is oligatory"
  <*> fieldDef "should_be_filled_by_sender" False (unsafeFromPersonalNumberField spnfShouldBeFilledBySender) "If should be filled by sender"
  <*> fieldDefBy "placements" [] (unsafeFromPersonalNumberField spnfPlacements) "Placements" (arrayOf unsonFieldPlacement)
  where
    unsafeFromPersonalNumberField :: (SignatoryPersonalNumberField -> a) -> SignatoryField -> a
    unsafeFromPersonalNumberField f (SignatoryPersonalNumberField a) = f a
    unsafeFromPersonalNumberField _ _ = $unexpectedError "unsafeFromPersonalNumberField"

unjsonCompanyNumberField :: Ap (FieldDef SignatoryField) SignatoryCompanyNumberField
unjsonCompanyNumberField = pure (\v  ob sfbs ps -> CompanyNumberField (unsafeSignatoryFieldID 0) v ob sfbs ps)
  <*> fieldDef "value" "" (unsafeFromCompanyNumberField scnfValue) "Value of the field"
  <*> fieldDef "is_obligatory" True (unsafeFromCompanyNumberField scnfObligatory) "If is oligatory"
  <*> fieldDef "should_be_filled_by_sender" False (unsafeFromCompanyNumberField scnfShouldBeFilledBySender) "If should be filled by sender"
  <*> fieldDefBy "placements" [] (unsafeFromCompanyNumberField scnfPlacements) "Placements" (arrayOf unsonFieldPlacement)
  where
    unsafeFromCompanyNumberField :: (SignatoryCompanyNumberField -> a) -> SignatoryField -> a
    unsafeFromCompanyNumberField f (SignatoryCompanyNumberField a) = f a
    unsafeFromCompanyNumberField _ _ = $unexpectedError "unsafeFromCompanyNumberField"


unjsonEmailField :: Ap (FieldDef SignatoryField) SignatoryEmailField
unjsonEmailField = pure (\v  ob sfbs ebs ps -> EmailField (unsafeSignatoryFieldID 0) v ob sfbs ebs ps)
  <*> fieldDef "value" "" (unsafeFromEmailField sefValue) "Value of the field"
  <*> fieldDef "is_obligatory" True (unsafeFromEmailField sefObligatory) "If is oligatory"
  <*> fieldDef "should_be_filled_by_sender" False (unsafeFromEmailField sefShouldBeFilledBySender) "If should be filled by sender"
  <*> fieldDef "editable_by_signatory" False (unsafeFromEmailField sefEditableBySignatory) "If is editable by signatory even if filled in"
  <*> fieldDefBy "placements" [] (unsafeFromEmailField sefPlacements) "Placements" (arrayOf unsonFieldPlacement)
  where
    unsafeFromEmailField :: (SignatoryEmailField -> a) -> SignatoryField -> a
    unsafeFromEmailField f (SignatoryEmailField a) = f a
    unsafeFromEmailField _ _ = $unexpectedError "unsafeFromEmailField"

unjsonMobileField :: Ap (FieldDef SignatoryField) SignatoryMobileField
unjsonMobileField = pure (\v ob sfbs ebs  ps -> MobileField (unsafeSignatoryFieldID 0) v ob sfbs ebs ps)
  <*> fieldDef "value" "" (unsafeFromMobileField smfValue) "Value of the field"
  <*> fieldDef "is_obligatory" True (unsafeFromMobileField smfObligatory) "If is oligatory"
  <*> fieldDef "should_be_filled_by_sender" False (unsafeFromMobileField smfShouldBeFilledBySender) "If should be filled by sender"
  <*> fieldDef "editable_by_signatory" False (unsafeFromMobileField smfEditableBySignatory) "If is editable by signatory even if filled in"
  <*> fieldDefBy "placements" [] (unsafeFromMobileField smfPlacements) "Placements" (arrayOf unsonFieldPlacement)


  where
    unsafeFromMobileField :: (SignatoryMobileField -> a) -> SignatoryField -> a
    unsafeFromMobileField f (SignatoryMobileField a) = f a
    unsafeFromMobileField _ _ = $unexpectedError "unsafeFromMobileField"


unjsonTextField :: Ap (FieldDef SignatoryField) SignatoryTextField
unjsonTextField  = pure (\n v  ob sfbs ps -> TextField  (unsafeSignatoryFieldID 0) n (v == "") v ob sfbs ps)
  <*> field "name"  (unsafeFromTextField  stfName) "Name of the field"
  <*> fieldDef "value" "" (unsafeFromTextField  stfValue) "Value of the field"
  <*> fieldDef "is_obligatory" True (unsafeFromTextField stfObligatory) "If is oligatory"
  <*> fieldDef "should_be_filled_by_sender" False (unsafeFromTextField stfShouldBeFilledBySender) "If should be filled by sender"
  <*> fieldDefBy "placements" [] (unsafeFromTextField stfPlacements) "Placements" (arrayOf unsonFieldPlacement)
  where
    unsafeFromTextField  :: (SignatoryTextField  -> a) -> SignatoryField -> a
    unsafeFromTextField  f (SignatoryTextField  a) = f a
    unsafeFromTextField  _ _ = $unexpectedError "unsafeFromTextField "

unjsonCheckboxField :: Ap (FieldDef SignatoryField) SignatoryCheckboxField
unjsonCheckboxField  = pure (\n v ob sfbs ps -> CheckboxField  (unsafeSignatoryFieldID 0) n v ob sfbs ps)
  <*> field "name"  (unsafeFromCheckboxField  schfName)  "Name of the field"
  <*> fieldDef "is_checked" False (unsafeFromCheckboxField  schfValue) "Value of the field"
  <*> fieldDef "is_obligatory" True (unsafeFromCheckboxField schfObligatory) "If is oligatory"
  <*> fieldDef "should_be_filled_by_sender" False (unsafeFromCheckboxField schfShouldBeFilledBySender) "If should be filled by sender"
  <*> fieldDefBy "placements" [] (unsafeFromCheckboxField schfPlacements) "Placements" (arrayOf (unjsonInvmapR validCheckboxPlacement id unsonFieldPlacement))
  where
    unsafeFromCheckboxField  :: (SignatoryCheckboxField  -> a) -> SignatoryField -> a
    unsafeFromCheckboxField  f (SignatoryCheckboxField  a) = f a
    unsafeFromCheckboxField  _ _ = $unexpectedError "unsafeFromCheckboxField "
    validCheckboxPlacement fp = if checkboxPlacementHasValidCheckboxRatio fp
      then return fp
      else fail "Checkbox placement has invalid wrel, hrel or fsrel"

unjsonSignatureField :: Ap (FieldDef SignatoryField) SignatorySignatureField
unjsonSignatureField  = pure (\n ob sfbs ps -> SignatureField  (unsafeSignatoryFieldID 0) n Nothing ob sfbs ps)
  <*> field "name"  (unsafeFromSignatureField  ssfName)  "Value of the field"
  <*  fieldReadOnlyOpt "signature" (unsafeFromSignatureField  ssfValue) "Uploaded file"
  <*> fieldDef "is_obligatory" True (unsafeFromSignatureField ssfObligatory) "If is oligatory"
  <*> fieldDef "should_be_filled_by_sender" False (unsafeFromSignatureField ssfShouldBeFilledBySender) "If should be filled by sender"
  <*> fieldDefBy "placements" [] (unsafeFromSignatureField ssfPlacements) "Placements" (arrayOf (unjsonInvmapR return id unsonFieldPlacement))
  where
    unsafeFromSignatureField  :: (SignatorySignatureField  -> a) -> SignatoryField -> a
    unsafeFromSignatureField  f (SignatorySignatureField  a) = f a
    unsafeFromSignatureField  _ _ = $unexpectedError "unsafeFromSignatureField "

unjsonRadioGroupField :: Ap (FieldDef SignatoryField) (Result SignatoryRadioGroupField)
unjsonRadioGroupField = pure (\n sv ps vs -> validateRadioGroup $ RadioGroupField (unsafeSignatoryFieldID 0) n sv ps vs)
  <*> field "name"  (unsafeFromRadioGroupField srgfName)  "Name of the field"
  <*> fieldOpt "selected_value" (unsafeFromRadioGroupField srgfSelectedValue) "Value of the selected radio button"
  <*> fieldDefBy "placements" [] (unsafeFromRadioGroupField srgfPlacements) "Placements" (arrayOf (unjsonInvmapR validRadiobuttonPlacement id unsonFieldPlacement))
  <*> field "values" (unsafeFromRadioGroupField srgfValues) "Possible values of radio buttons"
  where
    unsafeFromRadioGroupField :: (SignatoryRadioGroupField -> a) -> SignatoryField -> a
    unsafeFromRadioGroupField f (SignatoryRadioGroupField a) = f a
    unsafeFromRadioGroupField _ _ = $unexpectedError "unsafeFromRadioGroupField "
    validRadiobuttonPlacement fp = if radiobuttonPlacementHasValidRadiobuttonRatio fp
      then return fp
      else fail "Radiobutton placement has invalid wrel, hrel or fsrel"
    validateRadioGroup rg | hasDuplicates (srgfValues rg) = fail "Can't validate RadioGroup. Duplicate values."
                          | selectedValueIsNotInValues rg = fail "Can't validate RadioGroup. Selected value is not in values."
                          | anyValueEmpty rg = fail "Can't validate RadioGroup. Some values are empty."
                          | not (twoOrMoreValues rg) = fail "Can't validate RadioGroup. It has to have at least 2 possible values"
                          | not (eachValueHasMatchingPlacement rg) = fail "Can't validate RadioGroup. Different number of values and placements."
                          | not (allPlacementsOnSamePage rg) = fail "Can't validate RadioGroup. Placements are on different pages."
                          | otherwise = return rg
    hasDuplicates [] = False
    hasDuplicates (a:as) = a `elem` as || hasDuplicates as
    selectedValueIsNotInValues rg = case srgfSelectedValue rg of
      Nothing  -> False
      Just val -> val `notElem` srgfValues rg
    anyValueEmpty rg = any null $ srgfValues $ rg
    eachValueHasMatchingPlacement rg = (length $ srgfValues $ rg) == (length $ srgfPlacements rg)
    allPlacementsOnSamePage rg = 1 == length (nub $ placementpage <$> srgfPlacements rg)
    twoOrMoreValues rg = (length $ srgfValues $ rg) >= 2

fieldTypeToText :: FieldType -> T.Text
fieldTypeToText NameFT = "name"
fieldTypeToText CompanyFT = "company"
fieldTypeToText PersonalNumberFT = "personal_number"
fieldTypeToText CompanyNumberFT = "company_number"
fieldTypeToText EmailFT = "email"
fieldTypeToText MobileFT = "mobile"
fieldTypeToText TextFT = "text"
fieldTypeToText SignatureFT = "signature"
fieldTypeToText CheckboxFT = "checkbox"
fieldTypeToText RadioGroupFT = "radiogroup"


unsonFieldPlacement :: UnjsonDef FieldPlacement
unsonFieldPlacement =  objectOf $ pure (FieldPlacement tempPlacementID)
  <*> field "xrel" placementxrel "Relative x position"
  <*> field "yrel" placementyrel "Relative y position"
  <*> field "wrel" placementwrel "Relative width"
  <*> field "hrel" placementhrel "Relative height"
  <*> field "fsrel" placementfsrel "Relative font size"
  <*> field "page" placementpage "Page of placement"
  <*> fieldOptBy "tip" placementtipside "Should arrow point on field from left or right" unsonTipSide
  <*> fieldDefBy "anchors" [] placementanchors "Field placement anchors" (arrayOf unsonPlacementAnchor)


unsonPlacementAnchor :: UnjsonDef PlacementAnchor
unsonPlacementAnchor = objectOf $ pure PlacementAnchor
  <*> field "text" placementanchortext "Text to match with anchor"
  <*> field "index" placementanchorindex "Occurrence of text to match with"

unsonTipSide :: UnjsonDef TipSide
unsonTipSide = unjsonEnumBy "TipSide" [
      (LeftTip, "left")
    , (RightTip, "right")
    ]

-- Signatory fields value reading for signing. We need a dedicated datatype that will hold values that will be stored in files later

data SignatoryFieldTMPValue = StringFTV String
  | BoolFTV Bool
  | FileFTV BS.ByteString
  deriving (Eq, Ord, Show)


unsafeStringFromSignatoryFieldTMPValue :: SignatoryFieldTMPValue -> String
unsafeStringFromSignatoryFieldTMPValue (StringFTV a) = a
unsafeStringFromSignatoryFieldTMPValue (BoolFTV _) = $unexpectedError "unsafeStringFromSignatoryFieldTMPValue: Bool instead of Sting"
unsafeStringFromSignatoryFieldTMPValue (FileFTV _) = $unexpectedError "unsafeStringFromSignatoryFieldTMPValue: File instead of Sting"

unsafeBoolFromSignatoryFieldTMPValue :: SignatoryFieldTMPValue -> Bool
unsafeBoolFromSignatoryFieldTMPValue (BoolFTV a) = a
unsafeBoolFromSignatoryFieldTMPValue (StringFTV _) = $unexpectedError "unsafeBoolFromSignatoryFieldTMPValue: Sting instead of Bool"
unsafeBoolFromSignatoryFieldTMPValue (FileFTV _) = $unexpectedError "unsafeBoolFromSignatoryFieldTMPValue: File instead of Bool"

unsafeFileFromSignatoryFieldTMPValue :: SignatoryFieldTMPValue -> BS.ByteString
unsafeFileFromSignatoryFieldTMPValue (FileFTV a) = a
unsafeFileFromSignatoryFieldTMPValue (StringFTV _) = $unexpectedError "unsafeFileFromSignatoryFieldTMPValue: Sting instead of File"
unsafeFileFromSignatoryFieldTMPValue (BoolFTV _) = $unexpectedError "unsafeFileFromSignatoryFieldTMPValue: Bool instead of File"

newtype SignatoryFieldsValuesForSigning = SignatoryFieldsValuesForSigning [(FieldIdentity, SignatoryFieldTMPValue)] deriving Show

unjsonSignatoryFieldsValuesForSigning :: UnjsonDef SignatoryFieldsValuesForSigning
unjsonSignatoryFieldsValuesForSigning =  invmap SignatoryFieldsValuesForSigning (\(SignatoryFieldsValuesForSigning a) -> a) (arrayOf unjsonSignatoryFieldValue)

unjsonSignatoryFieldValue :: UnjsonDef (FieldIdentity,SignatoryFieldTMPValue)
unjsonSignatoryFieldValue = disjointUnionOf "type" [
    (fieldTypeToText NameFT, (\(fi,_) -> fieldTypeFromFieldIdentity fi == NameFT), (\(no,v) -> (NameFI no, StringFTV v)) <$> unjsonNameFieldFieldValue)
  , (fieldTypeToText CompanyFT, (\(fi,_) -> fieldTypeFromFieldIdentity fi == CompanyFT),  (\v -> (CompanyFI, StringFTV v)) <$> unjsonCompanyFieldFieldValue)
  , (fieldTypeToText PersonalNumberFT, (\(fi,_) -> fieldTypeFromFieldIdentity fi == PersonalNumberFT),  (\v -> (PersonalNumberFI, StringFTV v)) <$> unjsonPersonalNumberFieldFieldValue)
  , (fieldTypeToText CompanyNumberFT, (\(fi,_) -> fieldTypeFromFieldIdentity fi == CompanyNumberFT),  (\v -> (CompanyNumberFI, StringFTV v)) <$> unjsonCompanyNumberFieldFieldValue)
  , (fieldTypeToText EmailFT, (\(fi,_) -> fieldTypeFromFieldIdentity fi == EmailFT),  (\v -> (EmailFI, StringFTV v)) <$> unjsonEmailFieldFieldValue)
  , (fieldTypeToText MobileFT,(\(fi,_) -> fieldTypeFromFieldIdentity fi == MobileFT),  (\v -> (MobileFI, StringFTV v)) <$> unjsonMobileFieldFieldValue)
  , (fieldTypeToText TextFT,(\(fi,_) -> fieldTypeFromFieldIdentity fi == TextFT),  (\(n,v) -> (TextFI n, StringFTV v)) <$> unjsonTextFieldFieldValue)
  , (fieldTypeToText CheckboxFT,(\(fi,_) -> fieldTypeFromFieldIdentity fi == CheckboxFT),  (\(n,v) -> (CheckboxFI n, BoolFTV v)) <$> unjsonCheckboxFieldFieldValue)
  , (fieldTypeToText SignatureFT,(\(fi,_) -> fieldTypeFromFieldIdentity fi == SignatureFT),  (\(n,v) -> (SignatureFI n, FileFTV v)) <$> unjsonSignatureFieldFieldValue)
  , (fieldTypeToText RadioGroupFT,(\(fi,_) -> fieldTypeFromFieldIdentity fi == RadioGroupFT),  (\(n,v) -> (RadioGroupFI n, StringFTV v)) <$> unjsonRadioGroupFieldFieldValue)
  ]

unjsonNameFieldFieldValue :: Ap (FieldDef (FieldIdentity,SignatoryFieldTMPValue)) (NameOrder,String)
unjsonNameFieldFieldValue = pure (\no v ->(no,v))
  <*> field "order" (unsafeNameOrder . fst) "Order of name field"
  <*> field "value" (unsafeStringFromSignatoryFieldTMPValue .snd) "Value of the field"
  where
    unsafeNameOrder :: FieldIdentity -> NameOrder
    unsafeNameOrder (NameFI no) = no
    unsafeNameOrder _ = $unexpectedError "unsafeNameOrder"

unjsonCompanyFieldFieldValue :: Ap (FieldDef (FieldIdentity,SignatoryFieldTMPValue)) String
unjsonCompanyFieldFieldValue = field "value" (unsafeStringFromSignatoryFieldTMPValue .snd) "Value of the field"

unjsonPersonalNumberFieldFieldValue :: Ap (FieldDef (FieldIdentity,SignatoryFieldTMPValue)) String
unjsonPersonalNumberFieldFieldValue = field "value" (unsafeStringFromSignatoryFieldTMPValue .snd) "Value of the field"

unjsonCompanyNumberFieldFieldValue :: Ap (FieldDef (FieldIdentity,SignatoryFieldTMPValue)) String
unjsonCompanyNumberFieldFieldValue = field "value" (unsafeStringFromSignatoryFieldTMPValue .snd) "Value of the field"

unjsonEmailFieldFieldValue :: Ap (FieldDef (FieldIdentity,SignatoryFieldTMPValue)) String
unjsonEmailFieldFieldValue = field "value" (unsafeStringFromSignatoryFieldTMPValue .snd) "Value of the field"

unjsonMobileFieldFieldValue :: Ap (FieldDef (FieldIdentity,SignatoryFieldTMPValue)) String
unjsonMobileFieldFieldValue = field "value" (unsafeStringFromSignatoryFieldTMPValue .snd) "Value of the field"

unjsonTextFieldFieldValue :: Ap (FieldDef (FieldIdentity,SignatoryFieldTMPValue)) (String,String)
unjsonTextFieldFieldValue = pure (\no v ->(no,v))
  <*> field "name" (unsafeTextName . fst) "Name of text field"
  <*> field "value" (unsafeStringFromSignatoryFieldTMPValue .snd) "Value of the field"
  where
    unsafeTextName:: FieldIdentity -> String
    unsafeTextName (TextFI n) = n
    unsafeTextName _ = $unexpectedError "unsafeTextName"

unjsonCheckboxFieldFieldValue :: Ap (FieldDef (FieldIdentity,SignatoryFieldTMPValue)) (String,Bool)
unjsonCheckboxFieldFieldValue = pure (\no v ->(no,v))
  <*> field "name" (unsafeCheckboxName . fst) "Name of checkbox field"
  <*> field "is_checked" (unsafeBoolFromSignatoryFieldTMPValue .snd) "Value of the field"
  where
    unsafeCheckboxName:: FieldIdentity -> String
    unsafeCheckboxName (CheckboxFI n) = n
    unsafeCheckboxName _ = $unexpectedError "unsafeCheckboxName"

unjsonRadioGroupFieldFieldValue :: Ap (FieldDef (FieldIdentity,SignatoryFieldTMPValue)) (String,String)
unjsonRadioGroupFieldFieldValue = pure (\no v ->(no,v))
  <*> field "name" (unsafeRadioGroupName . fst) "Name of radio button group field"
  <*> field "selected_value" (unsafeStringFromSignatoryFieldTMPValue . snd) "Value of the field"
  where
    unsafeRadioGroupName:: FieldIdentity -> String
    unsafeRadioGroupName (RadioGroupFI n) = n
    unsafeRadioGroupName _ = $unexpectedError "unsafeRadioGroupName"

unjsonSignatureFieldFieldValue :: Ap (FieldDef (FieldIdentity,SignatoryFieldTMPValue)) (String,BS.ByteString)
unjsonSignatureFieldFieldValue = pure (\no v ->(no,v))
  <*> field "name" (unsafeSignatureName . fst) "Name of checkbox field"
  <*> fieldBy "signature" (unsafeFileFromSignatoryFieldTMPValue .snd) "Value of the field" unjsonImage
  where
    unsafeSignatureName:: FieldIdentity -> String
    unsafeSignatureName (SignatureFI n) = n
    unsafeSignatureName _ = $unexpectedError "unsafeSignatureName"
    unjsonImage :: UnjsonDef BS.ByteString
    -- JJ: what is "Screenshot" here?
    unjsonImage = SimpleUnjsonDef "Screenshot" parseImage (Aeson.String . decodeUtf8 . (RFC2397.encode "image/png"))
    parseImage :: Aeson.Value -> Result BS.ByteString
    parseImage (Aeson.String t ) = case RFC2397.decode $ encodeUtf8 t of
                                            Just (_,v) -> pure v
                                            _ -> fail "Can't parse image encoded as string. RFC2397 encoding expected"
    parseImage _ = fail "Can't parse image from something that is not string"
