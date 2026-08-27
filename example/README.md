# Flutter BLE Central Example

Scans for BLE peripherals, connects to one, and exchanges bytes with it over a
GATT service.

It is the central half of a pair. The other half is the example in
[flutter_ble_peripheral](https://github.com/juliansteenbakker/flutter_ble_peripheral);
see [Running the pair](#running-the-pair) below.

## Using it

1. **Permissions** — the app asks on launch, and the Permissions section can ask
   again. Android needs the Bluetooth and location permissions.
2. **Scan** — press Start. Devices appear as they are found, with their name,
   address and RSSI.
3. **Connect** — tap a device. The app connects, discovers its services, finds
   the TX/RX pair and subscribes to TX.
4. **Send** — enter hex bytes such as `01 02 03` and press Write to RX.
5. **Receive** — anything the peripheral notifies on TX appears below, most
   recent first.

Press Disconnect to drop the link and scan again.

## What it looks for

| | Value |
| --- | --- |
| Service | `bf27730d-860a-4e09-889c-2d8b6a9e0fe7` |
| TX, notify | `6e400003-b5a3-f393-e0a9-e50e24dcca9e` |
| RX, write | `6e400002-b5a3-f393-e0a9-e50e24dcca9e` |

These are what the `flutter_ble_peripheral` example serves, exported there as
`defaultTxCharacteristicUuid` and `defaultRxCharacteristicUuid`. They are the
Nordic UART Service characteristics.

The characteristics are looked up by uuid first and, failing that, by property:
whichever one notifies is treated as TX and whichever one accepts writes as RX.
So a peripheral serving its own layout under the same service still works.

## Running the pair

You need two devices; a phone and a Mac both work, and BLE does not work in a
simulator.

1. Run the `flutter_ble_peripheral` example on the first device and press Start.
2. Run this example on the second device and press Start.
3. Tap `Flutter BLE` in the list. The app connects and subscribes.
4. On the peripheral, the state chip turns to `connected` and its Send button
   becomes enabled.
5. Send bytes from either side; they appear on the other.

Both examples default to the same service UUID, so they find each other without
any configuration. Change it in one and you have to change it in the other.

## Running the pair unattended

`tool/interop_test.dart` does the same thing without the tapping, and checks
every call rather than just the round trip. From the root of the repository:

```sh
dart run tool/interop_test.dart
```

It lists the attached devices twice — once for the peripheral, once for the
central — launches `lib/interop_harness.dart` on each, and prints what every
call did:

```
  ✓ connect                                connected
  ✓ requestMtu                             515
  ✓ writeCharacteristic.withResponse       round trip of 3 bytes
  ✓ readPhy                                unsupported, as documented
```

A call the platform is documented not to serve passes when it throws
`unsupported` and fails when it answers, so a run also checks the support matrix
in the main README against what the plugin actually does. It exits non-zero if
anything failed, and keeps the full output of both halves under
`.dart_tool/interop_test/`.

If more than one peripheral is serving the harness service, the run says so and
fails rather than trusting the results: a second one is usually a copy of the app
left running from an earlier session, and it answers discovery and reads while
echoing nothing, which looks like a plugin bug rather than the stale process it
is.

It expects flutter_ble_peripheral beside this repository; pass
`--peripheral-path` if it is somewhere else. Pairing is left alone unless you
pass `--bonding`, since it needs someone to answer a system dialog and leaves a
bond behind.

## In code

```dart
await ble.connect(address: address);

final services = await ble.discoverServices(address);

await ble.setCharacteristicNotification(
  address: address,
  serviceUuid: serviceUuid,
  characteristicUuid: txUuid,
  enable: true,
);

ble.onCharacteristicValueChanged.listen((event) {
  // The peripheral notified on a characteristic.
});

await ble.writeCharacteristic(
  address: address,
  serviceUuid: serviceUuid,
  characteristicUuid: rxUuid,
  value: Uint8List.fromList([1, 2, 3]),
);
```

## Platform support

| | Scanning | Connecting |
| --- | --- | --- |
| Android | yes | yes |
| iOS | yes | not yet |
| macOS | yes | not yet |
| Windows | yes | not yet |

Connecting is Android only for now; see `GATT_PLAN.md` in the repository root.
