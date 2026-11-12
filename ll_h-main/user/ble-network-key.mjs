// Prints the H-series BLE 2.1 network signing key: one 32-byte key shared by every cabinet, derived from
// SWAP_BLE_SIGNING_KEY. Run on the server with the production environment file; the output is a secret for
// cabinet provisioning only. Usage: node --env-file=/etc/aihuandian/platform.env scripts/ble-network-key.mjs [keyId]
const [keyIdArgument] = process.argv.slice(2);
if (keyIdArgument && !/^[A-Za-z][A-Za-z0-9._-]{0,31}$/.test(keyIdArgument)) {
  // A cabinet code here means the old per-cabinet usage; the network key no longer depends on the cabinet.
  console.error('Usage: node --env-file=<env> scripts/ble-network-key.mjs [keyId]  (全网共用一把密钥，不再按柜号生成)');
  process.exit(2);
}
const { swapBluetoothSigningKeyId } = await import('../apps/api/src/config.js');
const { networkSigningKey } = await import('../apps/swap-service/src/bluetoothSigning.js');
const keyId = keyIdArgument || swapBluetoothSigningKeyId;
try {
  console.log(JSON.stringify({ keyId, keyHex: networkSigningKey(keyId).toString('hex') }));
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
