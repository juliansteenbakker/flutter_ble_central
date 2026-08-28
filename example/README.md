# Flutter BLE Central Example

Scans for BLE peripherals, connects to one, exchanges bytes with it, and plays
a game of pong over the link.

It is the central half of a pair. The other half is the example in
[flutter_ble_peripheral](https://github.com/juliansteenbakker/flutter_ble_peripheral);
see [Running the pair](#running-the-pair) below. The two apps are the same
instrument with one hue swapped — this one is cobalt, the peripheral is red —
so a pair of devices on a desk can be told apart at a glance.

## The four pages

| | What it is for |
| --- | --- |
| **Link** | Scan, and connect to what you find |
| **Data** | Everything you can do to a peripheral once connected |
| **Pong** | A game over the link, on one device or two |
| **Setup** | Scan settings, permissions and the adapter |

Across the top is a status rail that never scrolls: which half of the link this
app is, what the adapter is doing, and a live meter. Idle, the meter plots the
RSSI of the connection. During a game it plots the round trip. Either way, every
notification and every write raises a tick along its top edge, so the strip is
the ATT traffic rather than a decoration of it.

## Using it

1. **Setup** — the app runs the access check on launch, and the Permissions
   panel can run it again. Android needs the Bluetooth permissions; Windows
   needs location.
2. **Link** — press Start scan. Devices appear as they are found, strongest
   first. The green lamp beside a name means it is serving the example service.
3. **Connect** — tap a device. The app connects, discovers its services, finds
   the TX/RX pair and subscribes to TX.
4. **Data** — enter hex bytes such as `01 02 03` and press Write to RX.
   Anything the peripheral notifies on TX appears in the log below.

The Data page also carries every optional call the plugin has: MTU, link RSSI,
connection priority, pairing, PHY and reliable write. A call this platform does
not serve stays on the page, greyed and labelled with why, so the page doubles
as the support matrix.

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

## Pong

The Pong page plays a real game over the GATT link the rest of the app
demonstrates.

**One device** needs no radio and no second phone. A host and a guest run in the
same process, wired to each other through a loopback that encodes, delays and
decodes every message exactly as the radio would, and what you watch is the
guest's view — so the picture on screen is what came off the wire, not what the
simulation happened to be thinking. Both paddles play themselves.

**Two devices** is the real thing. The peripheral hosts: it simulates the ball
and both paddles and notifies the state twenty times a second. This app sends
only its paddle position, as a write without response, and draws what it is
told. It never simulates anything, so the two ends cannot disagree about the
score however bad the link gets. Drag anywhere across the court to move your
paddle.

Every message fits in 20 bytes, which is what an unnegotiated ATT MTU carries,
so a game works without asking for anything. The host paces itself by awaiting
each send rather than by a timer: the wire is never asked to carry more than it
is draining, and the state that gets dropped is always the older one.

`flutter test` covers the wire format and the physics; neither needs a radio.

## Running the pair

You need two devices; a phone and a Mac both work, and BLE does not work in a
simulator.

1. Run the `flutter_ble_peripheral` example on the first device and press Start
   advertising.
2. Run this example on the second device and press Start scan.
3. Tap `Flutter BLE` in the list. The app connects and subscribes.
4. On the peripheral, the state chip turns to `subscribed` and its Notify button
   becomes enabled.
5. Send bytes from either side on the Data page, or open Pong on both and play.

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
| iOS | yes | yes |
| macOS | yes | yes |
| Windows | yes | yes |

Scan settings are Android only; the other platforms scan the way they choose.
Connecting differs in places on Apple and Windows — see
[Connecting](../README.md#connecting) in the main README.

## Shared with flutter_ble_peripheral

`lib/shell/` and `lib/pong/` are byte-identical in both repositories, along with
`test/pong_test.dart` and the bundled fonts. An example cannot depend on a
package that is not on pub, and a path dependency on a sibling repository breaks
for anyone who clones only one, so the files are copied instead:

```sh
dart run tool/sync_example_shell.dart          # report drift
dart run tool/sync_example_shell.dart --write  # copy this repository's over
```

CI runs the first form, so the copies cannot quietly diverge. Change them here;
this repository is the copy of record.

## Fonts

Archivo and IBM Plex Mono, both under the SIL Open Font License, bundled in
`assets/fonts/` with their licences. Archivo ships as a single variable file
and is used at two widths: normal for text, and its widest for the stencilled
panel labels.
