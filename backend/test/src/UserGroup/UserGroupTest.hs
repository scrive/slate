{-# LANGUAGE OverloadedStrings #-}
module UserGroup.UserGroupTest (userGroupTests) where

import Data.Foldable (foldlM)
import Data.Int
import Test.Framework
import Test.QuickCheck

import DB
import Doc.SignatoryLinkID ()
import TestingUtil
import TestKontra as T
import User.Model
import UserGroup.Data
import UserGroup.Model

userGroupTests :: TestEnvSt -> Test
userGroupTests env  = testGroup "UserGroup"
  [ testThat "Test creating groups" env testCreateGroups
  , testThat "Test creating groups with users" env testCreateGroupsWithUsers
  , testThat "Test fetching all users of group" env testGetAllUsersOfTopGroup
  , testThat "Test fetching user group" env testGetUserGroup
  , testThat "Test fetching all groups of user" env testGetAllGroupsOfUser
  , testThat "Test moving a group" env testMoveGroup
  , testThat "Test moving a group cannot form a cycle" env testMoveGroupCycleError
  , testThat "Test find a parent group, where charging happens" env testFindInheritedPricePlan
  , testThat "Cannot delete a UserGroup with subgroups" env testCannotDeleteUserGroupWithSubgroups
  ]

testCreateGroups :: TestEnv ()
testCreateGroups = do
  -- create a 5 level tree, each parent 2 subgroups
  void $ foldlM createGroups [Nothing] [1..5]
  runQuery_ ("SELECT COUNT(*) FROM user_groups" :: SQL)
  groupcount <- fetchOne runIdentity
  assertEqual ("Created tree of groups") (31::Int64) groupcount
  where
    createGroups :: [Maybe UserGroupID] -> Int -> TestEnv [Maybe UserGroupID]
    createGroups mparent_ids level = (concat <$>) . forM mparent_ids $ \mparent_id -> do
      ug0 <- case level of
        1 -> unARootUserGroup <$> rand 10 arbitrary
        _ -> rand 10 arbitrary
      ug1 <- dbUpdate . UserGroupCreate . set ugParentGroupID mparent_id $ ug0
      return . replicate 2 . Just . get ugID $ ug1

testCreateGroupsWithUsers :: TestEnv ()
testCreateGroupsWithUsers = do
  -- create a 5 level tree, each parent 2 subgroups
  void $ foldlM createGroupsWithUsers [Nothing] [1..5]
  runQuery_ ("SELECT COUNT(*) FROM users" :: SQL)
  usercount <- fetchOne runIdentity
  assertEqual ("Created tree of groups and users") (31::Int64) usercount
  where
    createGroupsWithUsers :: [Maybe UserGroupID] -> Int -> TestEnv [Maybe UserGroupID]
    createGroupsWithUsers mparent_ids level = (concat <$>) . forM mparent_ids $ \mparent_id -> do
      ug0 <- case level of
        1 -> unARootUserGroup <$> rand 10 arbitrary
        _ -> rand 10 arbitrary
      ug1 <- dbUpdate . UserGroupCreate . set ugParentGroupID mparent_id $ ug0
      u <- addNewRandomUser
      void . dbUpdate $ SetUserGroup (userid u) (Just . get ugID $ ug1)
      return . replicate 2 . Just . get ugID $ ug1

testGetAllUsersOfTopGroup :: TestEnv ()
testGetAllUsersOfTopGroup = do
  -- create a 5 level tree, each parent 2 subgroups
  (_, (ugidtop:_)) <- foldlM createGroupsWithUsers ([Nothing],[]) [1..5]
  dus <- dbQuery . UserGroupGetAllUsersFromThisAndSubgroups $ ugidtop
  assertEqual ("Fetched all users of top group") 31 (length dus)
  where
    createGroupsWithUsers :: ([Maybe UserGroupID], [UserGroupID]) -> Int -> TestEnv ([Maybe UserGroupID], [UserGroupID])
    createGroupsWithUsers (mparent_ids, ugids) level = do
      new_ugids <- forM mparent_ids $ \mparent_id -> do
        ug0 <- case level of
          1 -> unARootUserGroup <$> rand 10 arbitrary
          _ -> rand 10 arbitrary
        ug1 <- dbUpdate . UserGroupCreate . set ugParentGroupID mparent_id $ ug0
        u <- addNewRandomUser
        void . dbUpdate $ SetUserGroup (userid u) (Just . get ugID $ ug1)
        return . get ugID $ ug1
      --      parents for groups in next level , all group ids created
      return (Just <$> (new_ugids ++ new_ugids), ugids ++ new_ugids)

testGetUserGroup :: TestEnv ()
testGetUserGroup = do
  ug0 <- unARootUserGroup <$> rand 10 arbitrary
  ug1 <- dbUpdate . UserGroupCreate $ ug0
  Just _ug2 <- dbQuery . UserGroupGet . get ugID $ ug1
  return ()

testGetAllGroupsOfUser :: TestEnv ()
testGetAllGroupsOfUser = do
  -- create a 5 level tree, each parent 2 subgroups
  (lastuid:_) <- (reverse . snd) <$> foldlM createGroupsWithUsers ([Nothing],[]) [1..5]
  Just lastu <- dbQuery . GetUserByID $ lastuid
  ugs <- dbQuery . UserGetAllParentGroups $ lastu
  assertEqual ("Fetched all groups of user") 5 (length ugs)
  where
    createGroupsWithUsers :: ([Maybe UserGroupID], [UserID]) -> Int -> TestEnv ([Maybe UserGroupID], [UserID])
    createGroupsWithUsers (mparent_ids, uids) level = do
      (new_ugids, new_uids) <- (unzip <$>) . forM mparent_ids $ \mparent_id -> do
        ug0 <- case level of
          1 -> unARootUserGroup <$> rand 10 arbitrary
          _ -> rand 10 arbitrary
        ug1 <- dbUpdate . UserGroupCreate . set ugParentGroupID mparent_id $ ug0
        u <- addNewRandomUser
        void . dbUpdate $ SetUserGroup (userid u) (Just . get ugID $ ug1)
        return (get ugID ug1, userid u)
      --      parents for groups in next level , all userids created
      return (Just <$> (new_ugids ++ new_ugids), uids ++ new_uids)

-- test moving a group to other part of the tree
--
-- before
--         0
--     1         2
--  3   4     5     6
-- 7 8 9 10 11 12 13 14
--
-- after
--         0
--               2
--            5     6
--          11 12 13 14
--                    1
--                 3   4
--                7 8 9 10

testMoveGroup :: TestEnv ()
testMoveGroup = do
  -- create a 4 level tree, each parent 2 subgroups
  (_, ugids) <- foldlM createGroupsWithUsers ([Nothing],[]) [1..4]
  -- take Root.Left group and move it to Root.Right....Right group
  Just ug1 <- dbQuery . UserGroupGet $ ugids !! 1
  _ <- dbUpdate . UserGroupUpdate . set ugParentGroupID (Just $ ugids !! 14) $ ug1
  -- parentpath of new leaf in moved group should be 6 items long
  Just (_ug10, parentugs) <- dbQuery . UserGroupGetWithParents $ ugids !! 10
  assertEqual ("Fetched all parents of leaf group") 6 (length parentugs)
  -- root still has 15 users
  us <- dbQuery . UserGroupGetAllUsersFromThisAndSubgroups $ ugids !! 0
  assertEqual ("Fetched all users of top group") 15 (length us)
  where
    createGroupsWithUsers :: ([Maybe UserGroupID], [UserGroupID]) -> Int -> TestEnv ([Maybe UserGroupID], [UserGroupID])
    createGroupsWithUsers (mparent_ids, ugids) level = do
      new_ugids <- forM mparent_ids $ \mparent_id -> do
        ug0 <- case level of
          1 -> unARootUserGroup <$> rand 10 arbitrary
          _ -> rand 10 arbitrary
        ug1 <- dbUpdate . UserGroupCreate . set ugParentGroupID mparent_id $ ug0
        u <- addNewRandomUser
        void . dbUpdate $ SetUserGroup (userid u) (Just . get ugID $ ug1)
        return . get ugID $ ug1
      --      parents for groups in next level , all group ids created
      return (Just <$> concatMap (replicate 2) new_ugids, ugids ++ new_ugids)

testMoveGroupCycleError :: TestEnv ()
testMoveGroupCycleError = do
  ugA0 <- unARootUserGroup <$> rand 10 arbitrary
  ugA <- dbUpdate . UserGroupCreate $ ugA0
  -- make B child of A
  ugB0 <- rand 10 arbitrary
  ugB <- dbUpdate . UserGroupCreate . set ugParentGroupID (Just . get ugID $ ugA) $ ugB0
  -- making A child of B fails
  assertRaisesKontra (\(UserGroupsFormCycle _) -> True) . dbUpdate . UserGroupUpdate . set ugParentGroupID (Just . get ugID $ ugB) $ ugA

testFindInheritedPricePlan :: TestEnv ()
testFindInheritedPricePlan = do
  ugA0 <- unARootUserGroup <$> rand 10 arbitrary
  ugA <- dbUpdate . UserGroupCreate $ ugA0
  ugB0 <- rand 10 arbitrary
  ugB <- dbUpdate . UserGroupCreate
    . set ugParentGroupID (Just . get ugID $ ugA)
    . set ugInvoicing     None
    $ ugB0
  Just ugwithparents <- dbQuery . UserGroupGetWithParents . get ugID $ ugB
  assertEqual "A is the charging group" (ugPaymentPlan ugA) . ugInherited ugPaymentPlan $ ugwithparents


testCannotDeleteUserGroupWithSubgroups :: TestEnv ()
testCannotDeleteUserGroupWithSubgroups = do
  ugA0 <- unARootUserGroup <$> rand 10 arbitrary
  ugA <- dbUpdate . UserGroupCreate $ ugA0
  -- make B child of A
  ugB0 <- rand 10 arbitrary
  ugB <- dbUpdate . UserGroupCreate . set ugParentGroupID (Just . get ugID $ ugA) $ ugB0
  commit -- so that raising exception will not take our data with it
  -- deleting group A raises exception
  assertRaisesDBException . runSQL_ $ "DELETE from user_groups where id = " <?> get ugID ugA
  commit
  -- deleting group B works
  runSQL_ $ "DELETE from user_groups where id = " <?> get ugID ugB


newtype ARootUserGroup = ARootUserGroup { unARootUserGroup :: UserGroup }

instance Arbitrary ARootUserGroup where
  arbitrary = (\ug pp ui address info -> ARootUserGroup $ ug {
      _ugInvoicing = Invoice pp
    , _ugUI        = ui
    , _ugSettings  = info
    , _ugAddress   = address
    })
    <$> arbitrary
    <*> arbitrary
    <*> arbitrary
    <*> arbitrary
    <*> arbitrary
