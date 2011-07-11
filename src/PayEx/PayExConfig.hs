-----------------------------------------------------------------------------
-- |
-- Module      :  PayEx.PayExConfig
-- Maintainer  :  mariusz@skrivapa.se
-- Stability   :  stable
-- Portability :  portable
--
--  Configuration of PayEx service
-----------------------------------------------------------------------------
module PayEx.PayExConfig(PayExConfig(..),getPayExConfig) where

import Control.Monad.IO.Class

{- | View of payment models (not editable) -}
getPayExConfig :: MonadIO m => m PayExConfig
getPayExConfig = return $ PayExConfig {
                            accountNumber  ="50251179"
                          , encryptionKey ="ArxLm7bk3craUnNU2K9r"
                          , vat = 0
                          , returnUrl = "http://localhost:8000"
                          , serverAddress = "https://test-external.payex.com"
                          , actionPrefix = "http://external.payex.com"
                         }

data PayExConfig = PayExConfig {
                     accountNumber::String,
                     encryptionKey::String,
                     vat::Integer,
                     returnUrl::String,
                     serverAddress::String,
                     actionPrefix::String
                     } deriving Show
