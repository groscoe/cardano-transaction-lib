module FromData
  ( class FromData
  , fromData
  ) where

import Prelude

import Data.Array as Array
import Data.BigInt (BigInt)
import Data.Either (Either(Left, Right))
import Data.List (List)
import Data.Map (Map)
import Data.Map as Map
import Data.Maybe (Maybe(Nothing, Just))
import Data.Ratio (Ratio, reduce)
import Data.Traversable (for, traverse)
import Data.Tuple (Tuple(Tuple))
import Data.Tuple.Nested (type (/\), (/\))
import Data.UInt (UInt)
import Data.Unfoldable (class Unfoldable)
import Helpers (bigIntToUInt)
import Prim.TypeError (class Fail, Text)
import Types.ByteArray (ByteArray, byteArrayToHex)
import Types.PlutusData (PlutusData(Bytes, Constr, List, Map, Integer))

class FromData (a :: Type) where
  fromData :: PlutusData -> Maybe a

instance FromData Void where
  fromData _ = Nothing

instance FromData Unit where
  fromData (List []) = Just unit
  fromData _ = Nothing

instance FromData Boolean where
  fromData (Constr n [])
    | n == zero = Just false
    | n == one = Just true
    | otherwise = Nothing
  fromData _ = Nothing

instance FromData a => FromData (Maybe a) where
  fromData (Constr n [ pd ]) = case fromData pd of
    Just Nothing | n == one -> Just Nothing
    Just (Just x) | n == zero -> Just (Just x) -- Just is one-indexed by Plutus
    _ -> Nothing
  fromData _ = Nothing

instance (FromData a, FromData b) => FromData (Either a b) where
  fromData (Constr n [ pd ]) = case fromData pd of
    Just (Left x) | n == zero -> Just (Left x)
    Just (Right x) | n == one -> Just (Right x)
    _ -> Nothing
  fromData _ = Nothing

instance Fail (Text "Int is not supported, use BigInt instead") => FromData Int where
  fromData _ = Nothing

instance FromData BigInt where
  fromData (Integer n) = Just n
  fromData _ = Nothing

instance FromData UInt where
  fromData (Integer n) = bigIntToUInt n
  fromData _ = Nothing

instance FromData a => FromData (Array a) where
  fromData = fromDataUnfoldable

instance FromData a => FromData (List a) where
  fromData = fromDataUnfoldable

instance (FromData a, FromData b) => FromData (a /\ b) where
  fromData (List [ a, b ]) = Tuple <$> fromData a <*> fromData b
  fromData _ = Nothing

instance (FromData k, Ord k, FromData v) => FromData (Map k v) where
  fromData (Map mp) = do
    Map.fromFoldable <$> for (Map.toUnfoldable mp :: Array _) \(k /\ v) ->
      Tuple <$> fromData k <*> fromData v
  fromData _ = Nothing

instance FromData ByteArray where
  fromData (Bytes res) = Just res
  fromData _ = Nothing

instance (Ord a, EuclideanRing a, FromData a) => FromData (Ratio a) where
  fromData (List [ a, b ]) = reduce <$> fromData a <*> fromData b
  fromData _ = Nothing

instance FromData PlutusData where
  fromData = Just

-- | This covers `Bech32` which is just a type alias for `String`
instance FromData String where
  fromData (Bytes res) = Just $ byteArrayToHex res
  fromData _ = Nothing

fromDataUnfoldable :: forall (a :: Type) (t :: Type -> Type). Unfoldable t => FromData a => PlutusData -> Maybe (t a)
fromDataUnfoldable (List entries) = Array.toUnfoldable <$> traverse fromData entries
fromDataUnfoldable _ = Nothing