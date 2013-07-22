{-# LANGUAGE NoImplicitPrelude, OverloadedStrings #-}
module Company.CompanyUI (
    CompanyUI(..)
  , SetCompanyUI(..)
  , GetCompanyUI(..)
  ) where

import Data.Typeable
import DB
import DB.SQL2
import Company.CompanyID
import Control.Monad.State
import OurPrelude

data CompanyUI = CompanyUI
  { companyemailbordercolour          :: Maybe String
  , companyemailfont                  :: Maybe String
  , companyemailbuttoncolour          :: Maybe String
  , companyemailemailbackgroundcolour :: Maybe String
  , companyemailbackgroundcolour      :: Maybe String
  , companyemailtextcolour            :: Maybe String
  , companyemaillogo                  :: Maybe Binary
  , companysignviewlogo               :: Maybe Binary
  , companysignviewtextcolour         :: Maybe String
  , companysignviewtextfont           :: Maybe String
  , companysignviewbarscolour         :: Maybe String
  , companysignviewbarstextcolour     :: Maybe String
  , companysignviewbackgroundcolour   :: Maybe String
  , companycustomlogo                 :: Maybe Binary
  , companycustombarscolour           :: Maybe String
  , companycustombarstextcolour       :: Maybe String
  , companycustombarssecondarycolour  :: Maybe String
  , companycustombackgroundcolour     :: Maybe String
} deriving (Eq, Ord, Show, Typeable)

data GetCompanyUI = GetCompanyUI CompanyID
instance MonadDB m => DBQuery m GetCompanyUI CompanyUI where
  query (GetCompanyUI cid) = do
    kRun_ $ sqlSelect "company_uis" $ do
      sqlWhereEq "company_id" cid
      selectCompanyUIsSelectors
    fetchCompanyUIs >>= exactlyOneObjectReturnedGuard

data SetCompanyUI = SetCompanyUI CompanyID CompanyUI
instance MonadDB m => DBUpdate m SetCompanyUI Bool where
  update (SetCompanyUI cid cui) = do
    kRun01 $ sqlUpdate "company_uis" $ do
      sqlSet "email_bordercolour" $ companyemailbordercolour cui
      sqlSet "email_font" $ companyemailfont cui
      sqlSet "email_buttoncolour" $ companyemailbuttoncolour cui
      sqlSet "email_emailbackgroundcolour" $ companyemailemailbackgroundcolour cui
      sqlSet "email_backgroundcolour" $ companyemailbackgroundcolour cui
      sqlSet "email_textcolour" $ companyemailtextcolour cui
      sqlSet "email_logo" $ companyemaillogo cui
      sqlSet "signview_logo" $ companysignviewlogo cui
      sqlSet "signview_textcolour" $ companysignviewtextcolour cui
      sqlSet "signview_textfont" $ companysignviewtextfont cui
      sqlSet "signview_barscolour" $ companysignviewbarscolour cui
      sqlSet "signview_barstextcolour" $ companysignviewbarstextcolour cui
      sqlSet "signview_backgroundcolour" $ companysignviewbackgroundcolour cui
      sqlSet "custom_logo" $ companycustomlogo cui
      sqlSet "custom_barscolour" $ companycustombarscolour cui
      sqlSet "custom_barstextcolour" $ companycustombarstextcolour cui
      sqlSet "custom_barssecondarycolour" $ companycustombarssecondarycolour cui
      sqlSet "custom_backgroundcolour" $ companycustombackgroundcolour cui
      sqlWhereEq "company_id" cid


selectCompanyUIsSelectors :: (SqlResult command) => State command ()
selectCompanyUIsSelectors = do
  sqlResult "company_uis.email_font"
  sqlResult "company_uis.email_bordercolour"
  sqlResult "company_uis.email_buttoncolour"
  sqlResult "company_uis.email_emailbackgroundcolour"
  sqlResult "company_uis.email_backgroundcolour"
  sqlResult "company_uis.email_textcolour"
  sqlResult "company_uis.email_logo"
  sqlResult "company_uis.signview_logo"
  sqlResult "company_uis.signview_textcolour"
  sqlResult "company_uis.signview_textfont"
  sqlResult "company_uis.signview_barscolour"
  sqlResult "company_uis.signview_barstextcolour"
  sqlResult "company_uis.signview_backgroundcolour"
  sqlResult "company_uis.custom_logo"
  sqlResult "company_uis.custom_barscolour"
  sqlResult "company_uis.custom_barstextcolour"
  sqlResult "company_uis.custom_barssecondarycolour"
  sqlResult "company_uis.custom_backgroundcolour"


fetchCompanyUIs :: MonadDB m => m [CompanyUI]
fetchCompanyUIs = kFold decoder []
  where
    decoder acc email_font
      email_bordercolour email_buttoncolour email_emailbackgroundcolour
      email_backgroundcolour email_textcolour email_logo signview_logo signview_textcolour
      signview_textfont signview_barscolour signview_barstextcolour
      signview_backgroundcolour custom_logo custom_barscolour custom_barstextcolour
      custom_barssecondarycolour custom_backgroundcolour = CompanyUI {
          companyemailfont = email_font
        , companyemailbordercolour = email_bordercolour
        , companyemailbuttoncolour = email_buttoncolour
        , companyemailemailbackgroundcolour = email_emailbackgroundcolour
        , companyemailbackgroundcolour = email_backgroundcolour
        , companyemailtextcolour = email_textcolour
        , companyemaillogo = email_logo
        , companysignviewlogo = signview_logo
        , companysignviewtextcolour = signview_textcolour
        , companysignviewtextfont = signview_textfont
        , companysignviewbarscolour = signview_barscolour
        , companysignviewbarstextcolour = signview_barstextcolour
        , companysignviewbackgroundcolour = signview_backgroundcolour
        , companycustomlogo  = custom_logo
        , companycustombarscolour = custom_barscolour
        , companycustombarstextcolour = custom_barstextcolour
        , companycustombarssecondarycolour = custom_barssecondarycolour
        , companycustombackgroundcolour = custom_backgroundcolour
        } : acc
