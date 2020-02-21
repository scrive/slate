module UserGroup.JSON (
    encodeUserGroup
  , updateUserGroupFromRequest
  , encodeUserGroupContactDetails
  , updateUserGroupContactDetailsFromRequest
  , encodeUserGroupSettings
  , updateUserGroupDataRetentionFromRequest
  , updateTag
  , TagOp(..)
  , TagUpdate(..)
) where

import Data.Aeson
import Data.Aeson.Encoding
import Data.Aeson.Types
import Data.Unjson
import qualified Data.HashMap.Strict as HM
import qualified Data.List.NonEmpty as L
import qualified Data.Set as S
import qualified Data.Text as T

import DataRetentionPolicy
import InputValidation
import UserGroup.Types
import qualified UserGroup.Internal as I

encodeUserGroup :: Bool -> UserGroupWithParents -> [UserGroup] -> Encoding
encodeUserGroup inheritable ugwp children =
  pairs
    $  ("id" .= (ug ^. #id))
    <> ("parent_id" .= (ug ^. #parentGroupID))
    <> ("name" .= (ug ^. #name))
    <> pair "children"        childrenEncoding
    <> pair "contact_details" (encodeUserGroupContactDetails inheritable ugwp)
    <> pair "settings" (encodeUserGroupSettings inheritable ugwp)
    <> pair "tags"            tags
  where
    ug               = ugwpUG ugwp
    childrenEncoding = flip list children
      $ \child -> pairs $ "id" .= (child ^. #id) <> "name" .= (child ^. #name)
    tags = flip list (S.toList $ ug ^. #externalTags)
      $ \tag -> pairs $ "name" .= (tag ^. #name) <> "value" .= (tag ^. #value)

updateUserGroupFromRequest :: UserGroup -> Value -> Either Text UserGroup
updateUserGroupFromRequest ug ugChanges =
  case update ugReq unjsonUserGroupRequestJSON ugChanges of
    (Result ugUpdated []) -> do
      let newTags = foldl' updateTag (S.toList $ ug ^. #externalTags) (reqTags ugUpdated)
      Right
        $ ug
        & (#parentGroupID .~ reqParentID ugUpdated)
        & (#name .~ reqName ugUpdated)
        & (#externalTags .~ S.fromList newTags)
    (Result _ problems) -> Left $ T.pack $ show problems
  where
    ugReq = UserGroupRequestJSON { reqParentID = ug ^. #parentGroupID
                                 , reqName     = ug ^. #name
                                 , reqTags     = []
                                 }

updateTag :: [UserGroupTag] -> TagUpdate -> [UserGroupTag]
updateTag tags (TagUpdate k op) = case op of
  SetTo v -> (I.UserGroupTag k v) : deleted
  Delete  -> deleted
  where deleted = filter (\ugt -> ugt ^. #name /= k) tags

data TagOp = SetTo Text | Delete
  deriving (Eq, Ord, Show)

instance ToJSON TagOp where
  toJSON = \case
    SetTo t -> String t
    Delete  -> Null

instance FromJSON TagOp where
  parseJSON = \case
    String s -> pure $ SetTo s
    Null     -> pure $ Delete
    invalid  -> typeMismatch "Expected a string or `null`" invalid

data TagUpdate = TagUpdate {
    tagName :: Text
  , tagValue :: TagOp
}

instance FromJSON TagUpdate where
  parseJSON = withObject "TagUpdate" $ \v -> TagUpdate <$> v .: "name" <*> v .: "value"

instance ToJSON TagUpdate where
  toJSON (TagUpdate name val) = object ["name" .= name, "value" .= val]

instance Unjson TagUpdate where
  unjsonDef = unjsonAeson

unjsonUserGroupRequestJSON :: UnjsonDef UserGroupRequestJSON
unjsonUserGroupRequestJSON =
  objectOf
    $   pure UserGroupRequestJSON
    <*> fieldOpt "parent_id" reqParentID "User Group ID"
    <*> field "name" reqName "User Group Name"
    <*> field "tags" reqTags "User Group Tags"

data UserGroupRequestJSON = UserGroupRequestJSON {
    reqParentID    :: Maybe UserGroupID
  , reqName        :: Text
  , reqTags        :: [TagUpdate]
  }

newtype UGAddrJSON = UGAddrJSON UserGroupAddress

instance ToJSON UGAddrJSON where
  toJSON _ = Null -- Redundant - Only needed to avoid `deriving Generic`
  toEncoding (UGAddrJSON addr) =
    pairs
      $  ("company_number" .= (addr ^. #companyNumber))
      <> ("company_name" .= (addr ^. #entityName))
      <> ("address" .= (addr ^. #address))
      <> ("zip" .= (addr ^. #zipCode))
      <> ("city" .= (addr ^. #city))
      <> ("country" .= (addr ^. #country))

encodeUserGroupContactDetails :: Bool -> UserGroupWithParents -> Encoding
encodeUserGroupContactDetails inheritable ugwp =
  pairs $ makeAddressJson inheritedFrom address <> inheritPreview
  where
    makeAddressJson mugid addr =
      "inherited_from" .= mugid <> "address" .= fmap UGAddrJSON addr
    mugAddr                  = ugwpUG ugwp ^. #address
    minherited               = ugwpAddressWithID <$> ugwpOnlyParents ugwp
    (inheritedFrom, address) = if isJust mugAddr
      then (Nothing, mugAddr) -- UG has own Address
      else L.unzip minherited -- UG has inherited Address
    inheritPreview = if inheritable
      then pair "inheritable_preview" $ case minherited of
        Nothing           -> null_ -- UG is root
        Just (ugid, addr) -> pairs $ makeAddressJson (Just ugid) (Just addr)
      else mempty

updateUserGroupContactDetailsFromRequest
  :: UserGroupAddress -> Value -> Maybe UserGroupAddress
updateUserGroupContactDetailsFromRequest ugAddr contactDetailsChanges =
  case contactDetailsChanges of
    Object obj -> do
      address <- HM.lookup "address" obj
      case update ugAddr unjsonUserGroupAddress address of
        (Result addressUpdated []) -> Just addressUpdated
        (Result _              _ ) -> Nothing
    _ -> Nothing

-- You must also update ToJSON UGAddrJSON above
unjsonUserGroupAddress :: UnjsonDef UserGroupAddress
unjsonUserGroupAddress =
  objectOf
    $   pure I.UserGroupAddress
    <*> fieldBy "company_number"
                (^. #companyNumber)
                "User Group Address Company Number"
                (unjsonWithValidationOrEmptyText asValidCompanyNumber)
    <*> fieldBy "entity_name"
                (^. #entityName)
                "User Group Address Entity Name"
                (unjsonWithValidationOrEmptyText asValidCompanyName)
    <*> fieldBy "address"
                (^. #address)
                "User Group Address Address"
                (unjsonWithValidationOrEmptyText asValidAddress)
    <*> fieldBy "zip"
                (^. #zipCode)
                "User Group Address Zip Code"
                (unjsonWithValidationOrEmptyText asValidZip)
    <*> fieldBy "city"
                (^. #city)
                "User Group Address City"
                (unjsonWithValidationOrEmptyText asValidCity)
    <*> fieldBy "country"
                (^. #country)
                "User Group Address Country"
                (unjsonWithValidationOrEmptyText asValidCountry)

newtype UGDRPJSON = UGDRPJSON DataRetentionPolicy

instance ToJSON UGDRPJSON where
  toJSON _ = Null -- Redundant - Only needed to avoid `deriving Generic`
  toEncoding (UGDRPJSON drp) =
    pairs
      $  ("idle_doc_timeout_preparation" .= (drp ^. #idleDocTimeoutPreparation))
      <> ("idle_doc_timeout_closed" .= (drp ^. #idleDocTimeoutClosed))
      <> ("idle_doc_timeout_canceled" .= (drp ^. #idleDocTimeoutCanceled))
      <> ("idle_doc_timeout_timedout" .= (drp ^. #idleDocTimeoutTimedout))
      <> ("idle_doc_timeout_rejected" .= (drp ^. #idleDocTimeoutRejected))
      <> ("idle_doc_timeout_error" .= (drp ^. #idleDocTimeoutError))
      <> ("immediate_trash" .= (drp ^. #immediateTrash))

-- This throws away all the fields except DRP
encodeUserGroupSettings :: Bool -> UserGroupWithParents -> Encoding
encodeUserGroupSettings inheritable ugwp =
  pairs $ makeDRPJson inheritedFrom msettings <> inheritPreview
  where
    makeDRPJson mugid msett =
      let drp = UGDRPJSON . view #dataRetentionPolicy <$> msett
      in  "inherited_from" .= mugid <> "data_retention_policy" .= drp
    mugSettings                = ugwpUG ugwp ^. #settings
    minherited                 = ugwpSettingsWithID <$> ugwpOnlyParents ugwp
    (inheritedFrom, msettings) = if isJust mugSettings
      then (Nothing, mugSettings) -- UG has own Settings
      else L.unzip minherited     -- UG has inherited Settings
    inheritPreview = if inheritable
      then pair "inheritable_preview" $ case minherited of
        Nothing           -> null_ -- UG is root
        Just (ugid, sett) -> pairs $ makeDRPJson (Just ugid) (Just sett)
      else mempty

updateUserGroupDataRetentionFromRequest
  :: DataRetentionPolicy -> Value -> Maybe DataRetentionPolicy
updateUserGroupDataRetentionFromRequest ugSett settingsChanges = case settingsChanges of
  Object obj -> do
    dataRetention <- HM.lookup "data_retention_policy" obj
    case update ugSett unjsonDataRetentionPolicy dataRetention of
      (Result dataRetentionUpdated []) -> Just dataRetentionUpdated
      (Result _                    _ ) -> Nothing
  _ -> Nothing
