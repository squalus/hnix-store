{-# LANGUAGE OverloadedStrings #-}

module SerializeSpec (spec) where

import Data.Fixed (Uni)
import Data.Serialize (Serialize(..))
import Data.Serialize.Get (Get, runGet)
import Data.Serialize.Put (Putter, runPut)
import Data.Text (Text)
import Data.Time (NominalDiffTime)
import Test.Hspec (Expectation, Spec, describe, it, parallel, shouldBe)
import Test.Hspec.QuickCheck (prop)
import Test.Hspec.Nix (roundtrips)
import Test.QuickCheck (arbitrary, forAll, suchThat)
import Test.QuickCheck.Instances ()

import qualified Data.Either
import qualified Data.HashSet
import qualified Data.Time.Clock.POSIX
import qualified System.Nix.Build

import System.Nix.Arbitrary ()
import System.Nix.Build (BuildMode(..), BuildStatus(..))
import System.Nix.Derivation (Derivation(..))
import System.Nix.Store.Remote.Arbitrary ()
import System.Nix.Store.Remote.Serialize (getDerivation, putDerivation)
import System.Nix.Store.Remote.Serialize.Prim
import System.Nix.Store.Remote.Types

-- | Test for roundtrip using @Putter@ and @Get@ functions
roundtrips2
  :: ( Eq a
     , Show a
     )
  => Putter a
  -> Get a
  -> a
  -> Expectation
roundtrips2 putter getter =
  roundtrips
    (runPut . putter)
    (runGet getter)

-- | Test for roundtrip using @Serialize@ instance
roundtripS
  :: ( Eq a
     , Serialize a
     , Show a
     )
  => a
  -> Expectation
roundtripS =
  roundtrips
    (runPut . put)
    (runGet get)

spec :: Spec
spec = parallel $ do
  describe "Prim" $ do
    prop "Int" $ roundtrips2 putInt (getInt @Int)
    prop "Bool" $ roundtrips2 putBool getBool
    prop "ByteString" $ roundtrips2 putByteString getByteString

    prop "UTCTime" $ do
      let
        -- scale to seconds and back
        toSeconds :: Int -> NominalDiffTime
        toSeconds n = realToFrac (toEnum n :: Uni)
        fromSeconds :: NominalDiffTime -> Int
        fromSeconds = (fromEnum :: Uni -> Int) . realToFrac

      roundtrips2
        (putTime . Data.Time.Clock.POSIX.posixSecondsToUTCTime . toSeconds)
        (fromSeconds . Data.Time.Clock.POSIX.utcTimeToPOSIXSeconds <$> getTime)

  describe "Combinators" $ do
    prop "Many" $ roundtrips2 (putMany putInt) (getMany (getInt @Int))
    prop "[ByteString]" $ roundtrips2 putByteStrings getByteStrings
    prop "Text" $ roundtrips2 putText getText
    prop "[Text]" $ roundtrips2 putTexts getTexts

    prop "StorePath" $ \sd ->
      roundtrips2
        (putPath sd)
        (Data.Either.fromRight undefined <$> getPath sd)

    prop "HashSet StorePath" $ \sd ->
      roundtrips2
        (putPaths sd)
        (Data.HashSet.map (Data.Either.fromRight undefined) <$> getPaths sd)

  describe "Serialize instances" $ do
    prop "Text" $ roundtripS @Text
    prop "BuildMode" $ roundtripS @BuildMode
    prop "BuildStatus" $ roundtripS @BuildStatus
    it "BuildResult" $
      forAll (arbitrary `suchThat` ((/= Just "") . System.Nix.Build.errorMessage))
      $ \br ->
          roundtripS
            -- fix time to 0 as we test UTCTime above
            $ br { System.Nix.Build.startTime = Data.Time.Clock.POSIX.posixSecondsToUTCTime 0
                 , System.Nix.Build.stopTime  = Data.Time.Clock.POSIX.posixSecondsToUTCTime 0
                 }

    prop "Derivation StorePath Text" $ \sd ->
      roundtrips2
        (putDerivation sd)
        (getDerivation sd)
        -- inputDrvs is not used in remote protocol serialization
        . (\drv -> drv { inputDrvs = mempty })

    describe "Logger" $ do
      prop "ActivityID" $ roundtripS @ActivityID
      prop "Field" $ roundtripS @Field
      prop "Verbosity" $ roundtripS @Verbosity

  describe "Enums" $ do
    let it' name constr value = it name $ runPut (put constr) `shouldBe` runPut (putInt @Int value)
    describe "BuildMode enum order matches Nix" $ do
      it' "Normal" BuildMode_Normal 0
      it' "Repair" BuildMode_Repair 1
      it' "Check"  BuildMode_Check  2

    describe "BuildStatus enum order matches Nix" $ do
      it' "Built"                  BuildStatus_Built                   0
      it' "Substituted"            BuildStatus_Substituted             1
      it' "AlreadyValid"           BuildStatus_AlreadyValid            2
      it' "PermanentFailure"       BuildStatus_PermanentFailure        3
      it' "InputRejected"          BuildStatus_InputRejected           4
      it' "OutputRejected"         BuildStatus_OutputRejected          5
      it' "TransientFailure"       BuildStatus_TransientFailure        6
      it' "CachedFailure"          BuildStatus_CachedFailure           7
      it' "TimedOut"               BuildStatus_TimedOut                8
      it' "MiscFailure"            BuildStatus_MiscFailure             9
      it' "DependencyFailed"       BuildStatus_DependencyFailed       10
      it' "LogLimitExceeded"       BuildStatus_LogLimitExceeded       11
      it' "NotDeterministic"       BuildStatus_NotDeterministic       12
      it' "ResolvesToAlreadyValid" BuildStatus_ResolvesToAlreadyValid 13
      it' "NoSubstituters"         BuildStatus_NoSubstituters         14

    describe "Verbosity enum order matches Nix" $ do
      it' "Error"     Verbosity_Error     0
      it' "Warn"      Verbosity_Warn      1
      it' "Notice"    Verbosity_Notice    2
      it' "Info"      Verbosity_Info      3
      it' "Talkative" Verbosity_Talkative 4
      it' "Chatty"    Verbosity_Chatty    5
      it' "Debug"     Verbosity_Debug     6
      it' "Vomit"     Verbosity_Vomit     7

