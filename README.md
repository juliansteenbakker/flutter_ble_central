# flutter_ble_central

[![pub package](https://img.shields.io/pub/v/flutter_ble_central?include_prereleases)](https://pub.dev/packages/flutter_ble_central)
[![CI](https://github.com/juliansteenbakker/flutter_ble_central/actions/workflows/ci.yml/badge.svg?branch=develop)](https://github.com/juliansteenbakker/flutter_ble_central/actions/workflows/ci.yml)
[![style: very good analysis](https://img.shields.io/badge/style-very_good_analysis-B22C89.svg)](https://pub.dev/packages/very_good_analysis)
[![GitHub Sponsors](https://img.shields.io/github/sponsors/juliansteenbakker)](https://github.com/sponsors/juliansteenbakker)

Scan for Bluetooth Low Energy devices from Flutter. This plugin puts the device in
**central** mode: it listens for advertisements from nearby peripherals and reports them
as `ScanResult`s. For the other direction, see
[flutter_ble_peripheral](https://pub.dev/packages/flutter_ble_peripheral).

| Platform | Minimum version | Notes |
| --- | --- | --- |
| Android | API 21 | Full `ScanSettings` support |
| iOS | 13.0 | Scan settings are ignored by CoreBluetooth |
| macOS | 10.14 | Scan settings are ignored by CoreBluetooth |
| Windows | Windows 10 | Scan settings are ignored |

## Installation

```bash
flutter pub add flutter_ble_central
```

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

Every permission call returns a `BluetoothCentralState`, which covers both the
permission result and the state of the adapter.

```dart
if (!await ble.isSupported) return;

var state = await ble.hasPermission();
if (state != BluetoothCentralState.granted) {
  state = await ble.requestPermission();
}

switch (state) {
  case BluetoothCentralState.granted:
  case BluetoothCentralState.ready:
    break;
  case BluetoothCentralState.turnedOff:
    await ble.enableBluetooth();       // Android and Windows only
  case BluetoothCentralState.permanentlyDenied:
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

`start` returns a `BluetoothCentralState`, so a scan that could not be started because
Bluetooth is off or unsupported is reported rather than thrown.

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

Connect to a device found by scanning, discover what it serves, then read, write or
subscribe. Android, iOS, macOS and Windows.

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

`address` is whatever the scan result reported, and its shape differs by platform: a
colon separated hardware address on Android, the decimal form of the same 48 bit value
on Windows, and on iOS and macOS the per-app identifier CoreBluetooth hands out
instead of an address, which only resolves for a peripheral this app has scanned or
connected to before. Pass it back unchanged rather than parsing it.

Also available: `readCharacteristic`, `readDescriptor`, `writeDescriptor`,
`getConnectionState`, `requestMtu` and `readRssi`.

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

What each platform carries differs:

| | Android | iOS, macOS | Windows |
| --- | --- | --- | --- |
| Pairing | yes | no | yes |
| Connection priority | yes | no | no |
| PHY control | Android 8.0+ | no | no |
| Reliable write | yes | no | no |
| `readRssi` | yes | yes | no |
| `requestMtu` | honours the size | reports the negotiated one | reports the negotiated one |

Anything unsupported throws `UNSUPPORTED` with an explanation rather than failing
silently. CoreBluetooth drives pairing from the system when a peripheral demands it;
Windows reports RSSI from advertisements only, never for a link already up.

### Streams

| Stream | Type | Platforms |
| --- | --- | --- |
| `onScanResult` | `ScanResult` | all |
| `onRawScanResult` | `dynamic`, straight from the platform | all |
| `onScanError` | `int`, an Android `SCAN_FAILED_*` code | Android only, `null` elsewhere |
| `onPeripheralStateChanged` | `CentralState` | all |
| `onConnectionStateChanged` | `ConnectionStateChange` | all |
| `onCharacteristicValueChanged` | `CharacteristicValue` | all |
| `onBondStateChanged` | `BondStateChange` | Android, Windows |

## API

| Member | Returns | Description |
| --- | --- | --- |
| `start({scanSettings})` | `BluetoothCentralState` | Starts scanning |
| `stop()` | `BluetoothCentralState` | Stops scanning |
| `isSupported` | `bool` | Whether BLE is available on this device |
| `isBluetoothOn` | `bool` | Whether the adapter is powered on |
| `hasPermission()` | `BluetoothCentralState` | Current permission and adapter state |
| `requestPermission()` | `BluetoothCentralState` | Prompts for the required permissions |
| `enableBluetooth({askUser})` | `bool` | Turns the adapter on (Android and Windows) |
| `openBluetoothSettings()` | `void` | Opens the system Bluetooth settings |
| `openAppSettings()` | `void` | Opens this app's settings page |
| `enableTimingStats` | `bool` field | Logs native timing information per scan result |

Connection members. All platforms unless noted:

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
| `readRssi(address)` | `int` | Signal strength of the connection. Not on Windows |
| `createBond(address)` | `void` | Starts pairing. Android, Windows |
| `removeBond(address)` | `void` | Removes the pairing. Android, Windows |
| `getBondState(address)` | `BondState` | Whether this device is paired. Android, Windows |
| `requestConnectionPriority({address, priority})` | `void` | Asks for a connection interval. Android only |
| `readPhy(address)` | `(tx, rx)` of `GattPhy` | The PHY in use. Android only |
| `setPreferredPhy({address, txPhy, rxPhy, phyOption})` | `void` | Asks to change it. Android only |
| `beginReliableWrite(address)` | `void` | Opens a reliable write transaction. Android only |
| `executeReliableWrite(address)` | `void` | Commits it. Android only |
| `abortReliableWrite(address)` | `void` | Drops it. Android only |

## Example

The [example app](example/lib/main.dart) is a full scanner with a GATT client on top:
permission handling, adapter state, live results, scan settings, and connecting to a
peripheral to exchange bytes. Run it with `cd example && flutter run`.

It is the central half of a pair. Run the
[flutter_ble_peripheral](https://github.com/juliansteenbakker/flutter_ble_peripheral)
example on a second device to connect to it; see
[the example README](example/README.md#running-the-pair).

## Contributing

Bug reports and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for the
branch layout, commit conventions and release process.

## License

BSD 3-Clause. See [LICENSE](LICENSE).
