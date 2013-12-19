module Resources where

import Data.IORef
import Test.Tasty
import Test.Tasty.Options
import Test.Tasty.Runners
import Test.Tasty.HUnit
import Control.Concurrent
import Control.Concurrent.STM
import Control.Monad.Writer
import qualified Data.IntMap as IntMap
import Data.Monoid
import qualified Data.Foldable as F

-- this is a dummy tree we use for testing
testTreeWithResources :: IORef Bool -> TestTree
testTreeWithResources ref =
  withResource (writeIORef ref True) (const $ writeIORef ref False) $
  testGroup "dummy"
    [ testCase "aaa" check
    , testCase "bbb" check
    , testCase "aab" $ threadDelay (10^5) >> check
    ]

  where
    check = readIORef ref >>= assertBool "ref is false!"

-- this is the actual test
testResources :: IORef Bool -> TestTree
testResources ref = testCase "Resources" $ do
  smap <- launchTestTree (setOption (parseTestPattern "aa") mempty) $ testTreeWithResources ref
  assertEqual "Number of tests to run" 2 (IntMap.size smap)
  rs <- runSMap smap
  assertBool "Resource is not available" $ getAll $ flip F.foldMap rs $ \r ->
    case r of
      Done (Result {resultSuccessful = True}) -> All True
      _ -> All False
  readIORef ref >>= assertBool "Resource was not released" . not

-- run tests, return successfulness
runSMap :: StatusMap -> IO [Status]
runSMap smap = atomically $
  execWriterT $ getApp $ flip F.foldMap smap $ \tv -> AppMonoid $ do
    s <- lift readTVar tv
    case s of
      NotStarted -> lift retry
      Executing {} -> lift retry
      finished -> tell [finished]
