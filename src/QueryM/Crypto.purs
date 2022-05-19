module QueryM.Crypto
  ( hashData
  , hashScript
  , datumHash
  , plutusHash
  , HashedData(..)
  , HashMethod(..)
  ) where

import Prelude

import Affjax as Affjax
import Affjax.RequestBody as Affjax.RequestBody
import Affjax.ResponseFormat as Affjax.ResponseFormat
import Control.Monad.Reader.Trans (asks)
import Data.Argonaut
  ( class DecodeJson
  , Json
  , JsonDecodeError(..)
  , decodeJson
  , caseJsonString
  , (:=)
  , (~>)
  , encodeJson
  )
import Data.Bifunctor (bimap)
import Data.Either (Either(..), hush, note, either)
import Data.Generic.Rep (class Generic)
import Data.Maybe (Maybe(..), maybe')
import Data.Newtype (class Newtype, unwrap, wrap)
import Data.Show.Generic (genericShow)
import Effect.Aff.Class (liftAff)
import Effect.Class (liftEffect)
import Effect.Exception (throw)
import QueryM (ClientError(..), QueryM, mkServerEndpointUrl, scriptToJson)
import QueryM.ServerConfig (mkHttpUrl)
import Serialization (toBytes) as Serialization
import Serialization.Hash (ScriptHash)
import Serialization.PlutusData (convertPlutusData) as Serialization
import Types.ByteArray (ByteArray, byteArrayToHex, hexToByteArray)
import Types.Datum (Datum, DatumHash)
import Types.Scripts (PlutusScript)
import Types.Transaction as Transaction
import Untagged.Union (asOneOf)

data HashMethod
  = Blake2b_256
  | Sha2_256
  | Sha3_256

derive instance Generic HashMethod _

instance Show HashMethod where
  show = genericShow

plutusHash
  :: HashMethod -> ByteArray -> QueryM (Maybe ByteArray)
plutusHash meth bytes = do
  url <- asks $ (_ <> "/" <> "plutus-hash") <<< mkHttpUrl <<< _.serverConfig
  let
    methJson :: Json
    methJson = case meth of
      Blake2b_256 -> encodeJson "Blake2b_256"
      Sha2_256 -> encodeJson "Sha2_256"
      Sha3_256 -> encodeJson "Sha3_256"

    bytesJson :: Json
    bytesJson = encodeJson $ byteArrayToHex bytes

    requestJson :: Json
    requestJson = "bytesToHash" := bytesJson
      ~> "methodToUse" := methJson

    reqBody :: Affjax.RequestBody.RequestBody
    reqBody = Affjax.RequestBody.Json requestJson
  response <- liftAff
    (Affjax.post Affjax.ResponseFormat.json url (pure reqBody))
  pure $ hush response >>= _.body >>> decodeJson >>> hush

hashData :: Datum -> QueryM (Maybe HashedData)
hashData datum = do
  body <-
    liftEffect $ byteArrayToHex <<< Serialization.toBytes <<< asOneOf
      <$> maybe' (\_ -> throw $ "Failed to convert plutus data: " <> show datum)
        pure
        (Serialization.convertPlutusData $ unwrap datum)
  url <- mkServerEndpointUrl "hash-data"
  -- get response json
  jsonBody <-
    liftAff
      ( Affjax.post Affjax.ResponseFormat.json url
          (Just $ Affjax.RequestBody.Json $ encodeJson body)
      ) <#> map \x -> x.body
  -- decode
  pure $ hush <<< decodeJson =<< hush jsonBody

-- | Hashes an Plutus-style Datum
datumHash :: Datum -> QueryM (Maybe DatumHash)
datumHash = map (map (Transaction.DataHash <<< unwrap)) <<< hashData

newtype HashedData = HashedData ByteArray

derive instance Newtype HashedData _
derive instance Generic HashedData _

instance Show HashedData where
  show = genericShow

instance DecodeJson HashedData where
  decodeJson =
    map HashedData <<<
      caseJsonString (Left err) (note err <<< hexToByteArray)
    where
    err :: JsonDecodeError
    err = TypeMismatch "Expected hex bytes (raw) of hashed data"

hashScript
  :: forall (a :: Type) (b :: Type)
   . Newtype a PlutusScript
  => Newtype b ScriptHash
  => a
  -> QueryM (Either ClientError b)
hashScript script = do
  url <- mkServerEndpointUrl "hash-script"
  let
    reqBody :: Maybe Affjax.RequestBody.RequestBody
    reqBody = Just
      $ Affjax.RequestBody.Json
      $ scriptToJson
      $ unwrap script
  liftAff (Affjax.post Affjax.ResponseFormat.json url reqBody)
    <#> either
      (Left <<< ClientHttpError)
      (bimap ClientDecodeJsonError wrap <<< decodeJson <<< _.body)
