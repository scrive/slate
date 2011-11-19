module CompanyAccounts.Model (
    module User.Model
  , module Company.Model
  , CompanyInvite(..)
  , AddCompanyInvite(..)
  , RemoveCompanyInvite(..)
  , GetCompanyInvite(..)
  , GetCompanyInvites(..)
  ) where

import Database.HDBC
import qualified Control.Exception as E
import qualified Data.ByteString.Char8 as BS


import Company.Model (CompanyID(..))
import DB.Classes
import DB.Utils
import User.Model (Email(..))

{- |
    A CompanyInvite is a record
    of an invitation made by a company
    to takeover an existing user.
-}
data CompanyInvite = CompanyInvite {
    invitedemail    :: Email --who was invited
  , invitedfstname  :: BS.ByteString --the fstname they were invited as
  , invitedsndname  :: BS.ByteString --the sndname they were invited as
  , invitingcompany :: CompanyID --the company they are invited to
  } deriving (Eq, Ord, Show)

data AddCompanyInvite = AddCompanyInvite CompanyInvite
instance DBUpdate AddCompanyInvite CompanyInvite where
  dbUpdate (AddCompanyInvite CompanyInvite{
      invitedemail
    , invitedfstname
    , invitedsndname
    , invitingcompany
    }) = do
    wrapDB $ \conn -> runRaw conn "LOCK TABLE companyinvites IN ACCESS EXCLUSIVE MODE"
    wrapDB $ \conn -> do
      _ <- run conn ("DELETE FROM companyinvites "
                      ++ "WHERE (company_id = ? AND email = ?)") $
                      [ toSql invitingcompany
                      , toSql invitedemail]
      _ <- run conn ("INSERT INTO companyinvites ("
                      ++ "  email"
                      ++ ", first_name"
                      ++ ", last_name"
                      ++ ", company_id) VALUES (?, ?, ?, ?)") $
                      [ toSql invitedemail
                      , toSql invitedfstname
                      , toSql invitedsndname
                      , toSql invitingcompany]
      return ()
    dbQuery (GetCompanyInvite invitingcompany invitedemail) >>= maybe (E.throw $ NoObject "") return

data RemoveCompanyInvite = RemoveCompanyInvite CompanyID Email
instance DBUpdate RemoveCompanyInvite () where
  dbUpdate (RemoveCompanyInvite companyid email) = do
  wrapDB $ \conn -> runRaw conn "LOCK TABLE companyinvites IN ACCESS EXCLUSIVE MODE"
  wrapDB $ \conn -> do
    _ <- run conn ("DELETE FROM companyinvites "
                    ++ "WHERE (company_id = ? AND email = ?)") $
                    [ toSql companyid
                    , toSql email]
    return ()
  dbQuery (GetCompanyInvite companyid email) >>= maybe (return ()) (const $ E.throw $ NoObject "")

data GetCompanyInvite = GetCompanyInvite CompanyID Email
instance DBQuery GetCompanyInvite (Maybe CompanyInvite) where
  dbQuery (GetCompanyInvite companyid email) = wrapDB $ \conn -> do
    st <- prepare conn $ selectCompanyInvitesSQL
      ++ "WHERE (ci.company_id = ? AND ci.email = ?)"
    _ <- execute st [toSql companyid, toSql email]
    cs <- fetchCompanyInvites st []
    oneObjectReturnedGuard cs

data GetCompanyInvites = GetCompanyInvites CompanyID
instance DBQuery GetCompanyInvites [CompanyInvite] where
    dbQuery (GetCompanyInvites companyid) = wrapDB $ \conn -> do
    st <- prepare conn $ selectCompanyInvitesSQL
      ++ "WHERE (ci.company_id = ?)"
    _ <- execute st [toSql companyid]
    fetchCompanyInvites st []

-- helpers
selectCompanyInvitesSQL :: String
selectCompanyInvitesSQL = "SELECT"
  ++ "  ci.email"
  ++ ", ci.first_name"
  ++ ", ci.last_name"
  ++ ", ci.company_id"
  ++ "  FROM companyinvites ci"
  ++ " "

fetchCompanyInvites :: Statement -> [CompanyInvite] -> IO [CompanyInvite]
fetchCompanyInvites st acc = fetchRow st >>= maybe (return acc) f
  where f [email, fstname, sndname, cid
         ] = fetchCompanyInvites st $ CompanyInvite {
             invitedemail = fromSql email
           , invitedfstname = fromSql fstname
           , invitedsndname = fromSql sndname
           , invitingcompany = fromSql cid
         } : acc
        f l = error $ "fetchCompanyInvites: unexpected row: "++show l
