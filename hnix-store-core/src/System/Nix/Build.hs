{-|
Description : Build related types
Maintainer  : srk <srk@48.io>
|-}
module System.Nix.Build
  ( BuildMode(..)
  , BuildStatus(..)
  , BuildResult(..)
  , buildSuccess
  ) where

import Data.Time (UTCTime)
import Data.Text (Text)
import GHC.Generics (Generic)

-- keep the order of these Enums to match enums from reference implementations
-- src/libstore/store-api.hh
data BuildMode = Normal | Repair | Check
  deriving (Eq, Generic, Ord, Enum, Show)

data BuildStatus =
    Built
  | Substituted
  | AlreadyValid
  | PermanentFailure
  | InputRejected
  | OutputRejected
  | TransientFailure -- possibly transient
  | CachedFailure    -- no longer used
  | TimedOut
  | MiscFailure
  | DependencyFailed
  | LogLimitExceeded
  | NotDeterministic
  | ResolvesToAlreadyValid
  | NoSubstituters
  deriving (Eq, Generic, Ord, Enum, Show)

-- | Result of the build
data BuildResult = BuildResult
  { -- | build status, MiscFailure should be default
    status             :: !BuildStatus
  , -- | possible build error message
    errorMessage       :: !(Maybe Text)
  , -- | How many times this build was performed
    timesBuilt         :: !Int
  , -- | If timesBuilt > 1, whether some builds did not produce the same result
    isNonDeterministic :: !Bool
  ,  -- Start time of this build
    startTime          :: !UTCTime
  ,  -- Stop time of this build
    stopTime           :: !UTCTime
  }
  deriving (Eq, Generic, Ord, Show)

buildSuccess :: BuildResult -> Bool
buildSuccess BuildResult {..} =
  status `elem` [Built, Substituted, AlreadyValid]
