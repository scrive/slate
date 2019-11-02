{-# LANGUAGE OverloadedStrings #-}
module AccessControl.APITest (accessControlApiTests) where

import Data.Aeson
import Happstack.Server
import Test.Framework
import qualified Data.HashMap.Strict as H
import qualified Data.Text as T
import qualified Data.Vector as V

import AccessControl.API
import AccessControl.Model
import AccessControl.Types
import DB
import TestingUtil
import TestKontra
import User.Email
import User.Model
import UserGroup.Model

accessControlApiTests :: TestEnvSt -> Test
accessControlApiTests env = testGroup
  "AccessControlAPI"
  [ -- AccessControl getuserroles tests
    testThat "non-admin and non-sales user can't view non-existent User's roles"
             env
             testNonAdminUserCannotViewRolesForNonExistentUser
  , testThat "non-admin and non-sales user can't view User's roles without permissions"
             env
             testNonAdminUserCannotViewUserRolesWithoutPermissions
  , testThat "non-admin and non-sales user can view own roles"
             env
             testNonAdminUserCanViewOwnRoles
  , testThat "usergroup admin can view roles of other usergroup member"
             env
             testUserGroupAdminCanViewRolesOfOtherUserGroupMember
  , testThat "usergroup member cannot view roles of other usergroup members"
             env
             testUserGroupMemberCannotViewRolesOfOtherUserGroupMembers
  , testThat "all roles are returned including roles generated by UserGroup inheritance"
             env
             testAllInheritedRolesAreReturned
  -- AccessControl get role by ID tests
  , testThat "non-admin and non-sales user can't view non-existent role"
             env
             testNonAdminUserCannotViewNonExistentRoles
  , testThat "non-admin and non-sales user can't view a role without permission"
             env
             testNonAdminUserCannotViewRoleWithoutPermissions
  , testThat "non-admin and non-sales user can view own role"
             env
             testNonAdminUserCanViewOwnRole
  , testThat "admin user can view role without permissions"
             env
             testAdminUserCanViewRoleWithoutPermissions
  -- AccessControl delete role by ID tests
  , testThat "non-admin and non-sales user can't delete non-existent role"
             env
             testNonAdminUserCannotDeleteNonExistentRoles
  , testThat "non-admin and non-sales user can't delete a role without permission"
             env
             testNonAdminUserCannotDeleteRoleWithoutPermissions
  , testThat "non-admin and non-sales user can delete own role"
             env
             testNonAdminUserCanDeleteOwnRole
  , testThat "admin user can delete role without permissions"
             env
             testAdminUserCanDeleteRoleWithoutPermissions
  -- AccessControl add role tests
  , testThat "non-admin and non-sales user can't add role for non-existent User (trg)"
             env
             testNonAdminUserCannotAddRoleFromNonExistentUser
  , testThat "non-admin and non-sales user can't add role for non-existent User (src)"
             env
             testNonAdminUserCannotAddRoleForNonExistentUser
  , testThat "admin user can't add role for non-existent User (trg)"
             env
             testAdminUserCannotAddRoleFromNonExistentUser
  , testThat "admin user can't add role for non-existent User (src)"
             env
             testAdminUserCannotAddRoleForNonExistentUser
  , testThat "non-admin and non-sales user can't add role without permissions on target"
             env
             testNonAdminUserCannotAddRoleWithoutPermissions
  , testThat "non-admin and non-sales user can add role with permissions on target"
             env
             testNonAdminUserCanAddRoleWithPermissions
  , testThat "admin user can add role without permissions on target"
             env
             testAdminUserCanAddRoleWithoutPermissions
  ]

-- AccessControl getuserroles tests

testNonAdminUserCannotViewRolesForNonExistentUser :: TestEnv ()
testNonAdminUserCannotViewRolesForNonExistentUser = do
  muser <- addNewUser "Dave" "Lister" "dave.lister@scrive.com"
  ctx   <- set #maybeUser muser <$> mkContext defaultLang
  req   <- mkRequest GET []
  res   <- fst <$> runTestKontra req ctx (accessControlAPIV2GetUserRoles uid)
  assertEqual "non-admin user can't view non-existent user's roles" 403 $ rsCode res
  where uid = unsafeUserID 123

testNonAdminUserCannotViewUserRolesWithoutPermissions :: TestEnv ()
testNonAdminUserCannotViewUserRolesWithoutPermissions = do
  muser <- addNewUser "Dave" "Lister" "dave.lister@scrive.com"
  uid2  <- userid . fromJust <$> addNewUser "Arnold" "Rimmer" "arnold.rimmer@scrive.com"
  ctx   <- set #maybeUser muser <$> mkContext defaultLang
  req   <- mkRequest GET []
  res   <- fst <$> runTestKontra req ctx (accessControlAPIV2GetUserRoles uid2)
  assertEqual "non-admin user can't view user's roles without permission" 403 $ rsCode res

testNonAdminUserCanViewOwnRoles :: TestEnv ()
testNonAdminUserCanViewOwnRoles = do
  muser <- addNewUser "The" "Cat" "the.cat@scrive.com"
  ctx   <- set #maybeUser muser <$> mkContext defaultLang
  req   <- mkRequest GET []
  let uid = userid $ fromJust muser
  res <- fst <$> runTestKontra req ctx (accessControlAPIV2GetUserRoles uid)
  assertEqual "non-admin user can view own roles" 200 $ rsCode res

testUserGroupAdminCanViewRolesOfOtherUserGroupMember :: TestEnv ()
testUserGroupAdminCanViewRolesOfOtherUserGroupMember = do
  (user, ug) <- addNewAdminUserAndUserGroup "Captain" "Hollister" emailAddress
  let uid1 = userid user
      ugid = ug ^. #ugID
  void . dbUpdate . AccessControlCreateForUser uid1 $ UserGroupAdminAR ugid
  user2 <- fromJust <$> addNewUserToUserGroup "Dwayne" "Dibley" emailAddress2 ugid
  let uid2 = userid user2
  ctx <- set #maybeUser (Just user) <$> mkContext defaultLang
  req <- mkRequest GET []
  res <- fst <$> runTestKontra req ctx (accessControlAPIV2GetUserRoles uid2)
  assertEqual "" 200 $ rsCode res
  where
    emailAddress  = "captain.hollister@scrive.com"
    emailAddress2 = "dwayne.dibley@scrive.com"

testUserGroupMemberCannotViewRolesOfOtherUserGroupMembers :: TestEnv ()
testUserGroupMemberCannotViewRolesOfOtherUserGroupMembers = do
  (user, ug) <- addNewAdminUserAndUserGroup "Captain" "Hollister" emailAddress
  let uid1 = userid user
      ugid = ug ^. #ugID
  void . dbUpdate . AccessControlCreateForUser uid1 $ UserGroupAdminAR ugid
  muser2 <- addNewCompanyUser "Dwayne" "Dibley" emailAddress2 ugid
  ctx    <- set #maybeUser muser2 <$> mkContext defaultLang
  req    <- mkRequest GET []
  res    <- fst <$> runTestKontra req ctx (accessControlAPIV2GetUserRoles uid1)
  assertEqual "usergroup member cannot view roles of other usergroup member" 403
    $ rsCode res
  where
    emailAddress  = "captain.hollister@scrive.com"
    emailAddress2 = "dwayne.dibley@scrive.com"

testAllInheritedRolesAreReturned :: TestEnv ()
testAllInheritedRolesAreReturned = do
  (userA, ugA) <- addNewAdminUserAndUserGroup "Captain"
                                              "Hollister"
                                              "captain.hollister@scrive.com"
  (_userB, ugB0) <- addNewAdminUserAndUserGroup "Dwayne"
                                                "Dibley"
                                                "dwayne.dibley@scrive.com"
  ctx <- set #maybeUser (Just userA) <$> mkContext defaultLang
  void . dbUpdate . UserGroupUpdate . set #ugParentGroupID (Just $ ugA ^. #ugID) $ ugB0
  req <- mkRequest GET []
  res <- fst <$> runTestKontra req ctx (accessControlAPIV2GetUserRoles $ userid userA)
  let
    Just  jsonRoles         = decode (rsBody res) :: Maybe Value
    Array vectorOfJsonRoles = jsonRoles
    roleTypes =
      map (\(Object o) -> H.lookup "role_type" o) . V.toList $ vectorOfJsonRoles
  assertEqual "2 UserAdminAR roles are returned" 2
    $ length
    . filter (== Just "user_admin")
    $ roleTypes

-- AccessControl get role by ID tests

testNonAdminUserCannotViewNonExistentRoles :: TestEnv ()
testNonAdminUserCannotViewNonExistentRoles = do
  muser <- addNewUser "Dave" "Lister" "dave.lister@scrive.com"
  ctx   <- set #maybeUser muser <$> mkContext defaultLang
  req   <- mkRequest GET []
  res   <- fst <$> runTestKontra req ctx (accessControlAPIV2Get roleId)
  assertEqual "non-admin user can't view non-existent role" 403 $ rsCode res
  where roleId = unsafeAccessRoleID 123

testNonAdminUserCannotViewRoleWithoutPermissions :: TestEnv ()
testNonAdminUserCannotViewRoleWithoutPermissions = do
  muser <- addNewUser "Dave" "Lister" "dave.lister@scrive.com"
  uid2  <- userid . fromJust <$> addNewUser "Arnold" "Rimmer" "arnold.rimmer@scrive.com"
  ctx   <- set #maybeUser muser <$> mkContext defaultLang
  role  <- fmap fromJust . dbUpdate . AccessControlCreateForUser uid2 $ UserAR uid2
  req   <- mkRequest GET []
  res   <- fst <$> runTestKontra req ctx (accessControlAPIV2Get $ getRoleId role)
  assertEqual "non-admin user can't view a role without permission" 403 $ rsCode res
  where
    getRoleId (AccessRoleUser roleId _ _) = roleId
    getRoleId _ = unexpectedError "This shouldn't happen"

testNonAdminUserCanViewOwnRole :: TestEnv ()
testNonAdminUserCanViewOwnRole = do
  muser <- addNewUser "Dave" "Lister" "dave.lister@scrive.com"
  ctx   <- set #maybeUser muser <$> mkContext defaultLang
  let uid = userid $ fromJust muser
  role <- fmap fromJust . dbUpdate . AccessControlCreateForUser uid $ UserAR uid
  req  <- mkRequest GET []
  res  <- fst <$> runTestKontra req ctx (accessControlAPIV2Get $ getRoleId role)
  assertEqual "non-admin user can view own role" 200 $ rsCode res
  where
    getRoleId (AccessRoleUser roleId _ _) = roleId
    getRoleId _ = unexpectedError "This shouldn't happen"

testAdminUserCanViewRoleWithoutPermissions :: TestEnv ()
testAdminUserCanViewRoleWithoutPermissions = do
  muser <- addNewUser "Dave" "Lister" emailAddress
  uid2  <- userid . fromJust <$> addNewUser "Arnold" "Rimmer" "arnold.rimmer@scrive.com"
  ctx   <- setUser muser <$> mkContext defaultLang
  role  <- fmap fromJust . dbUpdate . AccessControlCreateForUser uid2 $ UserAR uid2
  req   <- mkRequest GET []
  res   <- fst <$> runTestKontra req ctx (accessControlAPIV2Get $ getRoleId role)
  assertEqual "admin user can view a role without permission" 200 $ rsCode res
  where
    setUser muser = set #maybeUser muser . set #adminAccounts [Email emailAddress]
    emailAddress = "dave.lister@scrive.com"
    getRoleId (AccessRoleUser roleId _ _) = roleId
    getRoleId _ = unexpectedError "This shouldn't happen"

-- AccessControl delete role by ID tests

testNonAdminUserCannotDeleteNonExistentRoles :: TestEnv ()
testNonAdminUserCannotDeleteNonExistentRoles = do
  muser <- addNewUser "Dave" "Lister" "dave.lister@scrive.com"
  ctx   <- set #maybeUser muser <$> mkContext defaultLang
  req   <- mkRequest POST []
  res   <- fst <$> runTestKontra req ctx (accessControlAPIV2Delete roleId)
  assertEqual "non-admin user can't view non-existent role" 403 $ rsCode res
  where roleId = unsafeAccessRoleID 123

testNonAdminUserCannotDeleteRoleWithoutPermissions :: TestEnv ()
testNonAdminUserCannotDeleteRoleWithoutPermissions = do
  muser <- addNewUser "Dave" "Lister" "dave.lister@scrive.com"
  uid2  <- userid . fromJust <$> addNewUser "Arnold" "Rimmer" "arnold.rimmer@scrive.com"
  ctx   <- set #maybeUser muser <$> mkContext defaultLang
  role  <- fmap fromJust . dbUpdate . AccessControlCreateForUser uid2 $ UserAR uid2
  req   <- mkRequest POST []
  res   <- fst <$> runTestKontra req ctx (accessControlAPIV2Delete $ getRoleId role)
  assertEqual "non-admin user can't view a role without permission" 403 $ rsCode res
  where
    getRoleId (AccessRoleUser roleId _ _) = roleId
    getRoleId _ = unexpectedError "This shouldn't happen"

testNonAdminUserCanDeleteOwnRole :: TestEnv ()
testNonAdminUserCanDeleteOwnRole = do
  muser <- addNewUser "Dave" "Lister" "dave.lister@scrive.com"
  ctx   <- set #maybeUser muser <$> mkContext defaultLang
  let uid = userid $ fromJust muser
  role <- fmap fromJust . dbUpdate . AccessControlCreateForUser uid $ UserAR uid
  req  <- mkRequest POST []
  res  <- fst <$> runTestKontra req ctx (accessControlAPIV2Delete $ getRoleId role)
  assertEqual "non-admin user can view own role" 200 $ rsCode res
  where
    getRoleId (AccessRoleUser roleId _ _) = roleId
    getRoleId _ = unexpectedError "This shouldn't happen"

testAdminUserCanDeleteRoleWithoutPermissions :: TestEnv ()
testAdminUserCanDeleteRoleWithoutPermissions = do
  muser <- addNewUser "Dave" "Lister" emailAddress
  uid2  <- userid . fromJust <$> addNewUser "Arnold" "Rimmer" "arnold.rimmer@scrive.com"
  ctx   <- setUser muser <$> mkContext defaultLang
  role  <- fmap fromJust . dbUpdate . AccessControlCreateForUser uid2 $ UserAR uid2
  req   <- mkRequest POST []
  res   <- fst <$> runTestKontra req ctx (accessControlAPIV2Delete $ getRoleId role)
  assertEqual "admin user can view a role without permission" 200 $ rsCode res
  where
    setUser muser = set #maybeUser muser . set #adminAccounts [Email emailAddress]
    emailAddress = "dave.lister@scrive.com"
    getRoleId (AccessRoleUser roleId _ _) = roleId
    getRoleId _ = unexpectedError "This shouldn't happen"

-- AccessControl add role by ID tests

roleJSON :: UserID -> UserID -> String
roleJSON uid1 uid2 =
  "\
  \{\
  \    \"role_type\": \"user\",\
  \    \"source\": {\
  \        \"type\": \"user\",\
  \        \"id\": \""
    ++ src_uid
    ++ "\"\
  \    },\
  \    \"target\": {\
  \        \"type\": \"user\",\
  \        \"id\": \""
    ++ trg_uid
    ++ "\"\
  \    }\
  \}"
  where
    src_uid = show uid1
    trg_uid = show uid2

testNonAdminUserCannotAddRoleFromNonExistentUser :: TestEnv ()
testNonAdminUserCannotAddRoleFromNonExistentUser = do
  muser <- addNewUser "Dave" "Lister" "dave.lister@scrive.com"
  ctx   <- set #maybeUser muser <$> mkContext defaultLang
  let jsonString = roleJSON (userid $ fromJust muser) (unsafeUserID 321)
  req <- mkRequest POST [("role", inText $ T.pack jsonString)]
  res <- fst <$> runTestKontra req ctx (accessControlAPIV2Add)
  assertEqual "non-admin user can't add role for non-existent user (src)" 403 $ rsCode res

testNonAdminUserCannotAddRoleForNonExistentUser :: TestEnv ()
testNonAdminUserCannotAddRoleForNonExistentUser = do
  muser <- addNewUser "Dave" "Lister" "dave.lister@scrive.com"
  ctx   <- set #maybeUser muser <$> mkContext defaultLang
  let jsonString = roleJSON (unsafeUserID 321) (userid $ fromJust muser)
  req <- mkRequest POST [("role", inText $ T.pack jsonString)]
  res <- fst <$> runTestKontra req ctx (accessControlAPIV2Add)
  assertEqual "non-admin user can't add role for non-existent user (trg)" 403 $ rsCode res

testAdminUserCannotAddRoleFromNonExistentUser :: TestEnv ()
testAdminUserCannotAddRoleFromNonExistentUser = do
  muser <- addNewUser "Dave" "Lister" emailAddress
  ctx   <- setUser muser <$> mkContext defaultLang
  let jsonString = roleJSON (userid $ fromJust muser) (unsafeUserID 321)
  req <- mkRequest POST [("role", inText $ T.pack jsonString)]
  res <- fst <$> runTestKontra req ctx (accessControlAPIV2Add)
  assertEqual "admin user can't add role for non-existent user (src)" 403 $ rsCode res
  where
    emailAddress = "dave.lister@scrive.com"
    setUser muser = set #maybeUser muser . set #adminAccounts [Email emailAddress]

testAdminUserCannotAddRoleForNonExistentUser :: TestEnv ()
testAdminUserCannotAddRoleForNonExistentUser = do
  muser <- addNewUser "Dave" "Lister" emailAddress
  ctx   <- setUser muser <$> mkContext defaultLang
  let jsonString = roleJSON (unsafeUserID 321) (userid $ fromJust muser)
  req <- mkRequest POST [("role", inText $ T.pack jsonString)]
  res <- fst <$> runTestKontra req ctx (accessControlAPIV2Add)
  assertEqual "admin user can't add role for non-existent user (trg)" 403 $ rsCode res
  where
    emailAddress = "dave.lister@scrive.com"
    setUser muser = set #maybeUser muser . set #adminAccounts [Email emailAddress]

testNonAdminUserCannotAddRoleWithoutPermissions :: TestEnv ()
testNonAdminUserCannotAddRoleWithoutPermissions = do
  muser <- addNewUser "Dave" "Lister" "dave.lister@scrive.com"
  uid2  <- userid . fromJust <$> addNewUser "Arnold" "Rimmer" "arnold.rimmer@scrive.com"
  ctx   <- set #maybeUser muser <$> mkContext defaultLang
  let jsonString = roleJSON (userid $ fromJust muser) uid2
  req <- mkRequest POST [("role", inText $ T.pack jsonString)]
  res <- fst <$> runTestKontra req ctx (accessControlAPIV2Add)
  assertEqual "non-admin user can't add role without permissions (trg)" 403 $ rsCode res

testNonAdminUserCanAddRoleWithPermissions :: TestEnv ()
testNonAdminUserCanAddRoleWithPermissions = do
  muser <- addNewUser "Dave" "Lister" "dave.lister@scrive.com"
  uid2  <- userid . fromJust <$> addNewUser "Arnold" "Rimmer" "arnold.rimmer@scrive.com"
  ctx   <- set #maybeUser muser <$> mkContext defaultLang
  void . dbUpdate . AccessControlCreateForUser (userid $ fromJust muser) $ UserAR uid2
  let jsonString = roleJSON (userid $ fromJust muser) uid2
  req <- mkRequest POST [("role", inText $ T.pack jsonString)]
  res <- fst <$> runTestKontra req ctx (accessControlAPIV2Add)
  assertEqual "non-admin user can add role with permissions (trg)" 200 $ rsCode res

testAdminUserCanAddRoleWithoutPermissions :: TestEnv ()
testAdminUserCanAddRoleWithoutPermissions = do
  muser <- addNewUser "Dave" "Lister" emailAddress
  uid2  <- userid . fromJust <$> addNewUser "Arnold" "Rimmer" "arnold.rimmer@scrive.com"
  ctx   <- setUser muser <$> mkContext defaultLang
  let jsonString = roleJSON (userid $ fromJust muser) uid2
  req <- mkRequest POST [("role", inText $ T.pack jsonString)]
  res <- fst <$> runTestKontra req ctx (accessControlAPIV2Add)
  assertEqual "admin user can add role without permissions (trg)" 200 $ rsCode res
  where
    emailAddress = "dave.lister@scrive.com"
    setUser muser = set #maybeUser muser . set #adminAccounts [Email emailAddress]
