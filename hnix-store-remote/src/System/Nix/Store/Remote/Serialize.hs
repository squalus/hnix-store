{-# OPTIONS_GHC -Wno-orphans #-}
{-|
Description : Serialize instances for complex types
Maintainer  : srk <srk@48.io>
|-}
module System.Nix.Store.Remote.Serialize where

import Data.Serialize (Serialize(..))
import Data.Serialize.Get (Get)
import Data.Serialize.Put (Putter)
import Data.Text (Text)

import qualified Data.Bool
import qualified Data.Map
import qualified Data.Set
import qualified Data.Text
import qualified Data.Vector

import System.Nix.Derivation (Derivation(..), DerivationOutput(..))
import System.Nix.Build (BuildMode(..), BuildStatus(..), BuildResult(..))
import System.Nix.StorePath (StoreDir, StorePath)
import System.Nix.Store.Remote.Serialize.Prim

instance Serialize Text where
  get = getText
  put = putText

instance Serialize BuildMode where
  get = getEnum
  put = putEnum

instance Serialize BuildStatus where
  get = getEnum
  put = putEnum

instance Serialize BuildResult where
  get = do
    status <- get
    errorMessage <-
      (\em -> Data.Bool.bool (Just em) Nothing (Data.Text.null em)) 
      <$> get
    timesBuilt <- getInt
    isNonDeterministic <- getBool
    startTime <- getTime
    stopTime <- getTime
    pure $ BuildResult{..}

  put BuildResult{..} = do
    put status
    case errorMessage of
      Just err -> putText err
      Nothing -> putText mempty
    putInt timesBuilt
    putBool isNonDeterministic
    putTime startTime
    putTime stopTime

getDerivation
  :: StoreDir
  -> Get (Derivation StorePath Text)
getDerivation storeDir = do
  outputs <-
    Data.Map.fromList
    <$> (getMany $ do
          outputName <- get
          path <- getPathOrFail storeDir
          hashAlgo <- get
          hash <- get
          pure (outputName, DerivationOutput{..})
        )

  -- Our type is Derivation, but in Nix
  -- the type sent over the wire is BasicDerivation
  -- which omits inputDrvs
  inputDrvs <- pure mempty
  inputSrcs <-
    Data.Set.fromList
    <$> getMany (getPathOrFail storeDir)

  platform <- get
  builder <- get
  args <-
    Data.Vector.fromList
    <$> getMany get

  env <-
    Data.Map.fromList
    <$> getMany ((,) <$> get <*> get)
  pure Derivation{..}

putDerivation :: StoreDir -> Putter (Derivation StorePath Text)
putDerivation storeDir Derivation{..} = do
  flip putMany (Data.Map.toList outputs)
    $ \(outputName, DerivationOutput{..}) -> do
        putText outputName
        putPath storeDir path
        putText hashAlgo
        putText hash

  putMany (putPath storeDir) inputSrcs
  putText platform
  putText builder
  putMany putText args

  flip putMany (Data.Map.toList env)
    $ \(a1, a2) -> putText a1 *> putText a2
