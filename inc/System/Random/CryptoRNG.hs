{-# OPTIONS_GHC -fno-warn-orphans #-}
module System.Random.CryptoRNG where

import System.Random (StdGen, mkStdGen)
import Test.QuickCheck.Random

import Crypto.RNG (Random, random)
import KontraPrelude

instance Random StdGen where
  random = mkStdGen `liftM` random

instance Random QCGen where
  random = mkQCGen `liftM` random
