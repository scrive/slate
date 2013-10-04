-----------------------------------------------------------------------------
-- |
-- Module      :  Util.HasSomeCompanyInfo
-- Stability   :  development
-- Portability :  portable
--
-- Utility for abstracting away destructuring to get a
-- company number, and company name.
-----------------------------------------------------------------------------
module Util.HasSomeCompanyInfo (
    getCompanyName
  , getCompanyNumber
  , HasSomeCompanyInfo
  ) where

import Doc.DocStateData
import Company.Model
import Util.SignatoryLinkUtils

-- | Anything that might have a company name and number
class HasSomeCompanyInfo a where
  getCompanyName   :: a -> String
  getCompanyNumber :: a -> String

instance HasSomeCompanyInfo Company where
  getCompanyName   = companyname   . companyinfo
  getCompanyNumber = companynumber . companyinfo

instance HasSomeCompanyInfo (Maybe Company) where
  getCompanyName   = maybe "" getCompanyName
  getCompanyNumber = maybe "" getCompanyNumber

instance HasSomeCompanyInfo SignatoryLink where
  getCompanyName   = getValueOfType CompanyFT
  getCompanyNumber = getValueOfType CompanyNumberFT

instance HasSomeCompanyInfo Document where
  getCompanyName   doc = maybe "" getCompanyName   $ getAuthorSigLink doc
  getCompanyNumber doc = maybe "" getCompanyNumber $ getAuthorSigLink doc
