/* global require exports */

var lib;
if (typeof BROWSER_RUNTIME != 'undefined' && BROWSER_RUNTIME) {
    lib = require('@ngua/cardano-serialization-lib-browser');
} else {
    lib = require('@ngua/cardano-serialization-lib-nodejs');
}

const getNativeScriptAs = prop => maybe => ns => {
    const res = ns[prop]();
    return res == null ? maybe.nothing : maybe.just(res);
};

const call = property => object => object[property]();

exports.getScriptPubkey = getNativeScriptAs('as_script_pubkey');
exports.getScriptAll = getNativeScriptAs('as_script_all');
exports.getScriptAny = getNativeScriptAs('as_script_any');
exports.getScriptNOfK = getNativeScriptAs('as_script_n_of_k');
exports.getTimelockStart = getNativeScriptAs('as_timelock_start');
exports.getTimelockExpiry = getNativeScriptAs('as_timelock_expiry');
exports.scriptPubkey_addr_keyhash = call('addr_keyhash');