#!/usr/bin/env runghc

import System.Process
import System.Environment
import Data.List

allFlags :: [String]
allFlags = [ "test"
           , "server"
           , "mailing-server"
           , "pdfseal"
           , "cron"
           ]


main :: IO ()
main = do
  args <- getArgs
  let disabled = allFlags \\ args
  let flags = map (\f -> "-f-" ++ f) disabled
  _ <- rawSystem "cabal-dev" (["configure"] ++ flags ++ ["-fallow-warnings"])
  return ()
