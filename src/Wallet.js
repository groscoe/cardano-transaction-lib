// _enableNami :: Effect (Promise NamiConnection)
exports._enableNami = () => window.cardano.nami.enable();

// _getNamiAddress :: NamiConnection -> Effect (Promise String)
exports._getNamiAddress = (nami) => () =>
  nami.getUsedAddresses().then((addrs) => addrs[0]);
