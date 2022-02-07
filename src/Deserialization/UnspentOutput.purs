module Deserialization.UnspentOutput
  ( convertUnspentOutput
  , mkTransactionUnspentOutput
  ) where

import Prelude

import Data.BigInt as BigInt
import Data.Map (Map)
import Data.Map as Map
import Data.Maybe (Maybe)
import Data.Profunctor.Strong (first, (***))
import Data.Traversable (traverse)
import Data.Tuple (Tuple(Tuple))
import Data.Tuple.Nested (type (/\))
import Data.UInt as UInt
import Untagged.Union (asOneOf)

import Deserialization.Address (convertAddress)
import FfiHelpers (MaybeFfiHelper, maybeFfiHelper)
import Serialization (toBytes)
import Serialization.Types (Address, AssetName, Assets, BigNum, DataHash, MultiAsset, ScriptHash, TransactionHash, TransactionInput, TransactionOutput, TransactionUnspentOutput, Value)
import Types.ByteArray (ByteArray)
import Types.Transaction (DataHash(..), TransactionHash(..), TransactionInput(..), TransactionOutput(..)) as T
import Types.TransactionUnspentOutput (TransactionUnspentOutput(..)) as T
import Types.Value (Coin(..), CurrencySymbol(..), NonAdaAsset(..), TokenName(..), Value(..)) as T

convertUnspentOutput :: TransactionUnspentOutput -> Maybe T.TransactionUnspentOutput
convertUnspentOutput tuo = do
  input <- convertInput $ getInput tuo
  output <- convertOutput $ getOutput tuo
  pure $ T.TransactionUnspentOutput { input, output }

convertInput :: TransactionInput -> Maybe T.TransactionInput
convertInput input = do
  index <- UInt.fromInt' $ getTransactionIndex input
  pure $ T.TransactionInput
    { transaction_id: T.TransactionHash $ toBytes (asOneOf $ getTransactionHash input)
    , index
    }

convertOutput :: TransactionOutput -> Maybe T.TransactionOutput
convertOutput output = do
  address <- convertAddress $ getAddress output
  amount <- convertValue $ getAmount output
  let
    data_hash =
      getDataHash maybeFfiHelper output <#>
        asOneOf >>> toBytes >>> T.DataHash
  pure $ T.TransactionOutput { address, amount, data_hash }

convertValue :: Value -> Maybe T.Value
convertValue value = do
  coin <- BigInt.fromString $ bigNumToString $ getCoin value
  -- `serialization-lib` types
  multiasset :: Array (ScriptHash /\ Array (AssetName /\ BigNum)) <-
    getMultiAsset maybeFfiHelper value <#>
      extractMultiAsset Tuple >>> map (map (extractAssets Tuple))
  -- convert to domain types, except of BigNum
  let
    multiasset' =
      Map.fromFoldable $ multiasset <#>
        asOneOf >>> toBytes >>> T.CurrencySymbol ***
          Map.fromFoldable <<< map (first $ assetNameName >>> T.TokenName)
        :: Map T.CurrencySymbol (Map T.TokenName BigNum)
  -- convert BigNum values
  multiasset'' <- traverse
    (traverse (BigInt.fromString <<< bigNumToString))
    multiasset'
  pure $ T.Value (T.Coin coin) (T.NonAdaAsset multiasset'')

foreign import getInput :: TransactionUnspentOutput -> TransactionInput
foreign import getOutput :: TransactionUnspentOutput -> TransactionOutput
foreign import getTransactionHash :: TransactionInput -> TransactionHash
foreign import getTransactionIndex :: TransactionInput -> Int
foreign import getAddress :: TransactionOutput -> Address
foreign import getAmount :: TransactionOutput -> Value
foreign import getCoin :: Value -> BigNum
foreign import bigNumToString :: BigNum -> String
foreign import getMultiAsset :: MaybeFfiHelper -> Value -> Maybe MultiAsset
foreign import extractMultiAsset :: (forall a b. a -> b -> a /\ b) -> MultiAsset -> Array (ScriptHash /\ Assets)
foreign import extractAssets :: (forall a b. a -> b -> a /\ b) -> Assets -> Array (AssetName /\ BigNum)
foreign import assetNameName :: AssetName -> ByteArray
foreign import getDataHash :: MaybeFfiHelper -> TransactionOutput -> Maybe DataHash
foreign import mkTransactionUnspentOutput :: TransactionInput -> TransactionOutput -> TransactionUnspentOutput