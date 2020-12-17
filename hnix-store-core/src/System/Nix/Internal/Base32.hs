
module System.Nix.Internal.Base32 where

import           Data.Maybe             (fromMaybe)
import           Data.Bits              (shiftR)
import           Data.Word              (Word8)
import           Data.List              (unfoldr)
import qualified Data.ByteString        as BS
import qualified Data.ByteString.Char8  as BSC
import qualified Data.Text              as T
import qualified Data.Vector            as V
import           Numeric                (readInt)

-- omitted: E O U T
digits32 = V.fromList "0123456789abcdfghijklmnpqrsvwxyz"

-- | Encode a 'BS.ByteString' in Nix's base32 encoding
encode :: BS.ByteString -> T.Text
encode c = T.pack $ map char32 [nChar - 1, nChar - 2 .. 0]
  where
    -- Each base32 character gives us 5 bits of information, while
    -- each byte gives is 8. Because 'div' rounds down, we need to add
    -- one extra character to the result, and because of that extra 1
    -- we need to subtract one from the number of bits in the
    -- bytestring to cover for the case where the number of bits is
    -- already a factor of 5. Thus, the + 1 outside of the 'div' and
    -- the - 1 inside of it.
    nChar = fromIntegral $ ((BS.length c * 8 - 1) `div` 5) + 1

    byte = BS.index c . fromIntegral

    -- May need to switch to a more efficient calculation at some
    -- point.
    bAsInteger :: Integer
    bAsInteger = sum [fromIntegral (byte j) * (256 ^ j)
                     | j <- [0 .. BS.length c - 1]
                     ]

    char32 :: Integer -> Char
    char32 i = digits32 V.! digitInd
      where
        digitInd = fromIntegral $
                   bAsInteger
                   `div` (32^i)
                   `mod` 32

-- | Decode Nix's base32 encoded text
decode :: T.Text -> Either String BS.ByteString
decode what =
  if T.all (`elem` digits32) what
    then unsafeDecode what
    else Left "Invalid base32 string"

-- | Decode Nix's base32 encoded text
-- Doesn't check if all elements match `digits32`
unsafeDecode :: T.Text -> Either String BS.ByteString
unsafeDecode what =
  case readInt 32
         (`elem` digits32)
         (\c -> fromMaybe (error "character not in digits32") $
                  V.findIndex (==c) digits32)
         (T.unpack what)
    of
      [(i, _)] -> Right $ padded $ integerToBS i
      x        -> Left $ "Can't decode: readInt returned " ++ show x
  where
    padded x
      | BS.length x < decLen = x `BS.append` bstr
      | otherwise = x
     where
      bstr = BSC.pack $ take (decLen - BS.length x) (cycle "\NUL")

    decLen = T.length what * 5 `div` 8

-- | Encode an Integer to a bytestring
-- Similar to Data.Base32String (integerToBS) without `reverse`
integerToBS :: Integer -> BS.ByteString
integerToBS 0 = BS.pack [0]
integerToBS i
    | i > 0     = BS.pack $ unfoldr f i
    | otherwise = error "integerToBS not defined for negative values"
  where
    f 0 = Nothing
    f x = Just (fromInteger x :: Word8, x `shiftR` 8)
