# flutter_ble_central

[![pub package](https://img.shields.io/pub/v/flutter_ble_central?include_prereleases)](https://pub.dev/packages/flutter_ble_central)
[![CI](https://github.com/juliansteenbakker/flutter_ble_central/actions/workflows/ci.yml/badge.svg?branch=develop)](https://github.com/juliansteenbakker/flutter_ble_central/actions/workflows/ci.yml)
[![style: very good analysis](https://img.shields.io/badge/style-very_good_analysis-B22C89.svg)](https://pub.dev/packages/very_good_analysis)
[![GitHub Sponsors](https://img.shields.io/github/sponsors/juliansteenbakker)](https://github.com/sponsors/juliansteenbakker)

Scan for Bluetooth Low Energy devices from Flutter. This plugin puts the device in
**central** mode: it listens for advertisements from nearby peripherals and reports them
as `ScanResult`s. For the other direction, see
[flutter_ble_peripheral](https://pub.dev/packages/flutter_ble_peripheral).

| Platform | Minimum version | Scanning | Connecting |
| --- | --- | --- | --- |
| Android | API 21 | Full `ScanSettings` support | yes |
| iOS | 13.0 | Scan settings are ignored by CoreBluetooth | yes, with the [differences below](#connecting) |
| macOS | 10.15 | Scan settings are ignored by CoreBluetooth | yes, with the [differences below](#connecting) |
| Windows | Windows 10 | Scan settings are ignored | yes, with the [differences below](#connecting) |

## Installation

```bash
flutter pub add flutter_ble_central
```

Upgrading from 0.3.x? See [MIGRATION.md](MIGRATION.md).

## Platform setup

### Android

The plugin contributes `BLUETOOTH_SCAN` and `BLUETOOTH_CONNECT` to your merged manifest.
If you support API 30 and below, add the legacy permissions to
`android/app/src/main/AndroidManifest.xml` yourself, because scanning implies location
access on those API levels:

```xml
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />

<uses-permission-sdk-23
    android:name="android.permission.ACCESS_FINE_LOCATION"
    android:maxSdkVersion="30" />
<uses-permission-sdk-23
    android:name="android.permission.ACCESS_COARSE_LOCATION"
    android:maxSdkVersion="30" />
```

If your app never derives physical location from scan results, replace the plugin's
`BLUETOOTH_SCAN` declaration to add `neverForLocation`. This lets you drop the location
permissions entirely on API 31+:

```xml
<manifest xmlns:tools="http://schemas.android.com/tools">
    <uses-permission
        android:name="android.permission.BLUETOOTH_SCAN"
        android:usesPermissionFlags="neverForLocation"
        tools:targetApi="s"
        tools:node="replace" />
</manifest>
```

### iOS and macOS

Add a usage description to `Info.plist`, or the app is terminated the first time it
touches Bluetooth:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>This app needs Bluetooth to scan for nearby devices.</string>
```

On macOS, also tick the Bluetooth entitlement in **both**
`macos/Runner/Release.entitlements` and `macos/Runner/DebugProfile.entitlements`:

```xml
<key>com.apple.security.device.bluetooth</key>
<true/>
```

To stay connected once the app is no longer in front, add the background mode to
`ios/Runner/Info.plist`:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>bluetooth-central</string>
</array>
```

Without it iOS stops the scan and drops the connections when the app leaves the
foreground. What survives with it, and what does not, is under
[Background scanning](#background-scanning). macOS has no background modes, and keeps
scanning for as long as the app runs.

### Windows

No manifest changes are needed.

## Usage

### Getting started

`FlutterBleCentral` is a singleton, so calling the constructor anywhere gives you the
same instance.

```dart
import 'package:flutter_ble_central/flutter_ble_central.dart';

final ble = FlutterBleCentral();
```

### Permissions and adapter state

Every permission call returns a `CentralBluetoothState`, which covers both the
permission result and the state of the adapter.

```dart
if (!await ble.isSupported) return;

var state = await ble.hasPermission();
if (state != CentralBluetoothState.granted) {
  state = await ble.requestPermission();
}

switch (state) {
  case CentralBluetoothState.granted:
  case CentralBluetoothState.ready:
    break;
  case CentralBluetoothState.turnedOff:
    await ble.enableBluetooth();       // Android and Windows only
  case CentralBluetoothState.permanentlyDenied:
    await ble.openAppSettings();
  default:
    return;
}
```

`openBluetoothSettings()` opens the system Bluetooth page, and `isBluetoothOn` reports
whether the adapter is powered on.

On Android, the state you get back depends on what the user has done before:

| Situation | previouslyRequested | previouslyGranted | rationale | Result |
| --- | --- | --- | --- | --- |
| First time | false | false | false | `denied` |
| User denies | true | false | true | `denied` |
| User denies with "don't ask again" | true | false | false | `permanentlyDenied` |
| User grants, then revokes in settings | true/false | true | false | `denied` |
| Already granted | true/false | true | n/a | `granted` |

That table needs an activity: the rationale check comes from one. From a foreground
service, or any other engine with no activity attached, `hasPermission()` and
`requestPermission()` report whether the permissions are granted and nothing finer,
since a service cannot prompt. `start()` works there all the same — scanning and
connecting need no activity — but the permissions have to have been granted by a screen
that ran earlier, and it answers `denied` rather than asking when they are not.
Bluetooth has to be on for the same reason: below Android 13 `enableBluetooth()` can
still turn it on without asking, and above that Google removed the programmatic path,
so there it answers `false`.

### Scanning

Listen to `onScanResult` before calling `start`, so no advertisement is missed.

```dart
final subscription = ble.onScanResult.listen((result) {
  final name = result.scanRecord?.deviceName;
  print('${result.device?.address} $name ${result.rssi} dBm');
});

await ble.start();

// later
await ble.stop();
await subscription.cancel();
```

`start` returns a `CentralBluetoothState`, so a scan that could not be started because
Bluetooth is off or unsupported is reported rather than thrown.

A peripheral is reported once per advertising packet, so the same address arrives many
times over a scan. Each result carries everything that peripheral has said so far, not
only what the last packet held: a peripheral usually splits its advertisement in two,
putting the service uuids in one packet and the local name in the other, and the
halves are folded together for you. Keeping the newest result per address gives you
both. `deviceName` is null until a name is heard, which for an Android peripheral is
never — it has no way to advertise one of its own.

### Scan settings

`ScanSettings` mirrors Android's
[`ScanSettings`](https://developer.android.com/reference/android/bluetooth/le/ScanSettings)
and is ignored on the other platforms.

```dart
await ble.start(
  scanSettings: ScanSettings(
    scanMode: ScanMode.scanModeLowLatency,
    callbackType: CallbackType.allMatches,
    matchMode: MatchMode.aggressive,
    reportDelay: 0,
    legacyMode: true,
    useLightweightScanResult: false,
  ),
);
```

Set `useLightweightScanResult: true` to receive only the fields most apps need
(address, manufacturer data, service UUIDs). It measurably reduces work per
advertisement when scanning in a busy environment.

### Connecting

Connect to a device found by scanning, discover what it serves, then read, write
or subscribe. Every platform serves this.

Uuids may be given in the 16 bit (`'2a37'`), 32 bit or 128 bit form; a short one is
expanded onto the Bluetooth Base UUID before it is matched against what was discovered,
so it finds the same characteristic either way.

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

await ble.disconnect(address);
```

`connect` returns as soon as the request is in. Wait for
`onConnectionStateChanged` to report `GattConnectionState.connected` before
discovering services.

Also available: `readCharacteristic`, `readDescriptor`, `writeDescriptor`,
`getConnectionState`, `requestMtu` and `readRssi`.

Windows differs in a few places, because WinRT does not expose the same controls:

- There is no explicit connect. `connect` resolves the peripheral and asks the
  radio to hold the link open, so it reports `connecting` and the link comes up
  when the first read or discovery goes out. Wait for `onConnectionStateChanged`
  the same way as on Android.
- `discoverServices` has to run before a read, a write or a subscription. Windows
  hands back the characteristic objects as part of discovery, and there is nothing
  to address without them.
- `connect` ignores its `timeout`. There is no attempt to give up on: the radio
  is asked to hold the link open and keeps trying until `disconnect`. Android and
  Apple both stop after `timeout` seconds.
- `requestMtu` reports the MTU the connection already negotiated; the size asked
  for is ignored, since Windows negotiates it itself.
- `readRssi`, `readPhy`, `setPreferredPhy`, `requestConnectionPriority`,
  `getBondState` and the reliable write trio throw a `PlatformException` with code
  `unsupported`. None of them has a WinRT equivalent.
- `createBond` accepts only the pairing ceremony that needs no passkey, which
  covers most peripherals. One that asks for a passkey or a numeric comparison is
  refused, and the refusal arrives on `onBondStateChanged` as `none`.

Apple differs too, because Core Bluetooth hides more of the link:

- The address is the peripheral's Core Bluetooth identifier, which is per app and
  per install rather than a hardware address. It is only good on the device that
  produced it, and only for a peripheral this app has already scanned for.
- `discoverServices` has to run before a read, a write or a subscription, the same
  as on Windows.
- `requestMtu` reports the MTU the link negotiated; the size asked for is ignored,
  since Core Bluetooth negotiates it itself.
- Core Bluetooth has no pairing API at all, so `createBond`, `removeBond` and
  `getBondState` throw `unsupported` and `onBondStateChanged` never emits. Pairing
  happens on its own when a peripheral asks for it.
- `readPhy`, `setPreferredPhy`, `requestConnectionPriority` and the reliable write
  trio throw `unsupported`. `readRssi` does work, unlike on Windows.

### Pairing, PHY and reliable write

```dart
await ble.createBond(address);
ble.onBondStateChanged.listen((event) => print(event.state));

await ble.requestConnectionPriority(
  address: address,
  priority: ConnectionPriority.high,
);

await ble.setPreferredPhy(
  address: address,
  txPhy: GattPhy.le2M,
  rxPhy: GattPhy.le2M,
);
final phy = await ble.readPhy(address);

// Queued on the peripheral and echoed back for verification, then committed.
await ble.beginReliableWrite(address);
await ble.writeCharacteristic(...);
await ble.executeReliableWrite(address);
```

Pairing usually needs the user to confirm it, so `createBond` returns as soon as the
request is in and the outcome arrives on `onBondStateChanged`. `setPreferredPhy` is
likewise a request: read it back with `readPhy` to see what the peripheral and the
controller agreed on. PHY control needs Android 8.0.

### Background scanning

On Android a scan and its connections belong to the process, so both keep running while
the app sits in the background and end when the system kills the process. Starting one
from a service rather than from an activity is not supported: `start()` needs an
activity to check permissions against, and answers with a `No activity` error without
one, so the scan has to be started while the app is in front.

On iOS everything stops with the foreground unless the app declares the
`bluetooth-central` background mode, and even with it a connection and a scan fare
differently.

A connection survives. Core Bluetooth keeps it open, goes on delivering notifications,
and can relaunch the app to hand it back, which is what the background mode is worth
here today.

A scan does not, and this package cannot yet make it. iOS reports a backgrounded scan's
results only for peripherals matching the service uuids that scan named, and
`ScanSettings` has no service filter to name them with, so a scan carries on being
delivered while the app is in front and goes quiet when it is not. Two more rules apply
once a filter exists: `allowDuplicates` is ignored in the background, so results arrive
once per peripheral per scan window with their advertisements merged rather than on
every advertisement, and the scan runs at the system's convenience, so discovery takes
longer.

Declaring the background mode also lets the plugin register a restore identifier with
Core Bluetooth, which is what allows iOS to relaunch the app into the background and
hand the connected peripherals back. The plugin points each restored peripheral at its
delegate again, so notifications keep arriving, and keeps the services that were
discovered before, so nothing has to be discovered a second time. Connection state is
only published when it changes, and a restored connection changed before the app was
up, so a new `onConnectionStateChanged` listener is given the state of everything
currently held.

### Streams

| Stream | Type | Platforms |
| --- | --- | --- |
| `onScanResult` | `ScanResult` | all |
| `onRawScanResult` | `dynamic`, straight from the platform | all |
| `onScanError` | `int`, an Android `SCAN_FAILED_*` code | Android only, `null` elsewhere |
| `onCentralStateChanged` | `CentralState` | all |
| `onConnectionStateChanged` | `ConnectionStateChange` | all |
| `onCharacteristicValueChanged` | `CharacteristicValue` | all |
| `onBondStateChanged` | `BondStateChange` | Android and Windows |

## API

| Member | Returns | Description |
| --- | --- | --- |
| `start({scanSettings})` | `CentralBluetoothState` | Starts scanning |
| `stop()` | `CentralBluetoothState` | Stops scanning |
| `isSupported` | `bool` | Whether BLE is available on this device |
| `isBluetoothOn` | `bool` | Whether the adapter is powered on |
| `hasPermission()` | `CentralBluetoothState` | Current permission and adapter state |
| `requestPermission()` | `CentralBluetoothState` | Prompts for the required permissions |
| `enableBluetooth({askUser})` | `bool` | Turns the adapter on (Android and Windows) |
| `openBluetoothSettings()` | `void` | Opens the system Bluetooth settings |
| `openAppSettings()` | `void` | Opens this app's settings page |
| `enableTimingStats` | `bool` field | Logs native timing information per scan result |

Connection members. Android serves all of them. Windows serves everything down to
`removeBond`, and Apple everything down to `readRssi`; both throw `unsupported`
for the rest:

| Member | Returns | Description |
| --- | --- | --- |
| `connect({address, autoConnect, timeout})` | `void` | Opens a GATT connection |
| `disconnect(address)` | `void` | Closes it |
| `getConnectionState(address)` | `GattConnectionState` | The current link state |
| `discoverServices(address)` | `List<GattService>` | What the peripheral serves |
| `readCharacteristic({...})` | `Uint8List` | Reads a characteristic |
| `writeCharacteristic({..., withoutResponse})` | `void` | Writes one |
| `setCharacteristicNotification({..., enable})` | `void` | Subscribes or unsubscribes |
| `readDescriptor({...})` | `Uint8List` | Reads a descriptor |
| `writeDescriptor({...})` | `void` | Writes one |
| `requestMtu({address, mtu})` | `int` | The negotiated MTU |
| `createBond(address)` | `void` | Starts pairing |
| `removeBond(address)` | `void` | Removes the pairing |
| `readRssi(address)` | `int` | Signal strength of the connection |
| `getBondState(address)` | `BondState` | Whether this device is paired |
| `requestConnectionPriority({address, priority})` | `void` | Asks for a connection interval |
| `readPhy(address)` | `(tx, rx)` of `GattPhy` | The PHY in use |
| `setPreferredPhy({address, txPhy, rxPhy, phyOption})` | `void` | Asks to change it |
| `beginReliableWrite(address)` | `void` | Opens a reliable write transaction |
| `executeReliableWrite(address)` | `void` | Commits it |
| `abortReliableWrite(address)` | `void` | Drops it |

## Example

The [example app](example/README.md) is a full scanner with a GATT client on top,
laid out over four pages: scanning and connecting, the whole GATT surface, a game of
pong over the link, and scan settings with permissions. Every optional call is on the
page whether or not this platform serves it, so the app doubles as the support matrix.
Run it with `cd example && flutter run`.

It is the central half of a pair. Run the
[flutter_ble_peripheral](https://github.com/juliansteenbakker/flutter_ble_peripheral)
example on a second device to connect to it; see
[the example README](example/README.md#running-the-pair).

## Contributing

Bug reports and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for the
branch layout, commit conventions and release process.

## License

BSD 3-Clause. See [LICENSE](LICENSE).
