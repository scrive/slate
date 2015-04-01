{-# LANGUAGE OverlappingInstances #-}
module Crypto.RNG.Class where

import Control.Monad.Trans
import Crypto.Random.DRBG
import Data.ByteString (ByteString)

import KontraPrelude

-- | Monads carrying around the RNG state.
class Monad m => CryptoRNG m where
  -- | Generate given number of cryptographically secure random bytes.
  randomBytes :: CryptoRNG m
              => ByteLength -- ^ number of bytes to generate
              -> m ByteString

-- | Generic, overlapping instance.
instance (
    Monad (t m)
  , MonadTrans t
  , CryptoRNG m
  ) => CryptoRNG (t m) where
    randomBytes = lift . randomBytes
