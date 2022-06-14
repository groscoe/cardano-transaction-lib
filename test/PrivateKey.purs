module Test.PrivateKey where

import Prelude

import Cardano.Types.Transaction
  ( Ed25519Signature(Ed25519Signature)
  , Transaction(Transaction)
  , TransactionWitnessSet(TransactionWitnessSet)
  , Vkeywitness(Vkeywitness)
  )
import Contract.Address (NetworkId(..))
import Contract.Monad (configWithLogLevel, runContract)
import Contract.Transaction (signTransaction)
import Contract.Wallet (mkKeyWalletFromFile)
import Data.Lens (_2, _Just, (^?))
import Data.Lens.Index (ix)
import Data.Lens.Iso.Newtype (unto)
import Data.Lens.Record (prop)
import Data.Log.Level (LogLevel(..))
import Data.Maybe (Maybe(Just), maybe)
import Effect.Class (liftEffect)
import Effect.Exception (throw)
import Mote (group, test)
import Test.Fixtures (txFixture1)
import Test.Spec.Assertions (shouldEqual)
import TestM (TestPlanM)
import Type.Proxy (Proxy(..))

suite :: TestPlanM Unit
suite = do
  group "PrivateKey" $ do
    test "privateKeyFromFile" do
      wallet <- mkKeyWalletFromFile "fixtures/test/parsing/PrivateKey/skey.json"
        >>= maybe (liftEffect $ throw "Unable to read PrivateKey") pure
      cfg <- configWithLogLevel TestnetId wallet Trace
      runContract cfg do
        mbTx <- signTransaction txFixture1
        let
          mbSignature =
            mbTx ^? _Just
              <<< unto Transaction
              <<< prop (Proxy :: Proxy "witnessSet")
              <<< unto TransactionWitnessSet
              <<< prop (Proxy :: Proxy "vkeys")
              <<< _Just
              <<< ix 0
              <<< unto Vkeywitness
              <<<
                _2
        mbSignature `shouldEqual` Just
          ( Ed25519Signature
              "ed25519_sig1w7nkmvk57r6094j9u85r4pddve0hg3985ywl9yzwecx03aa9fnfspl9zmtngmqmczd284lnusjdwkysgukxeq05a548dyepr6vn62qs744wxz"
          )