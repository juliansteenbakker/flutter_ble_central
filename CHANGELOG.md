# Changelog

## [1.1.0](https://github.com/juliansteenbakker/flutter_ble_central/compare/v1.0.0...v1.1.0) (2026-09-03)


### Features

* **apple:** restore connections after a background relaunch ([31a668e](https://github.com/juliansteenbakker/flutter_ble_central/commit/31a668ee0f6134800d7387101ed6237acbc65ae5))
* **apple:** restore connections after a background relaunch ([ae26f30](https://github.com/juliansteenbakker/flutter_ble_central/commit/ae26f303caeefdcf0b926f24f322cbb62267def3))
* filter a scan by service uuid ([#138](https://github.com/juliansteenbakker/flutter_ble_central/issues/138)) ([86554ad](https://github.com/juliansteenbakker/flutter_ble_central/commit/86554adbce3182e0c8f7497decbdb400adb62446))


### Bug Fixes

* **android:** file a read under the uuid its callback reports ([#140](https://github.com/juliansteenbakker/flutter_ble_central/issues/140)) ([ddccc8d](https://github.com/juliansteenbakker/flutter_ble_central/commit/ddccc8de274d5a41340cada5f3d5221d01e2d942))
* **android:** key a read by the uuid its callback reports ([#141](https://github.com/juliansteenbakker/flutter_ble_central/issues/141)) ([2a1f246](https://github.com/juliansteenbakker/flutter_ble_central/commit/2a1f246f4ffc03747845c36911ad9c7000dff7fc))
* **android:** match short uuids and run without an activity ([#136](https://github.com/juliansteenbakker/flutter_ble_central/issues/136)) ([d82dbe9](https://github.com/juliansteenbakker/flutter_ble_central/commit/d82dbe9fa3a27993fbe9ef1bffe0a0e7d9663a62))

## [1.0.0](https://github.com/juliansteenbakker/flutter_ble_central/compare/v0.3.3...v1.0.0) (2026-09-02)


### ⚠ BREAKING CHANGES

The state types were renamed so this package and `flutter_ble_peripheral` no longer
declare colliding names. Both old names stay as deprecated aliases in 1.0 and are
removed in the next breaking release, so 0.3.x code keeps compiling with a warning.

* `BluetoothCentralState` is renamed to `CentralBluetoothState`. The entries and their order are unchanged, so existing switches keep working; only the type name moves ([#116](https://github.com/juliansteenbakker/flutter_ble_central/issues/116), [#128](https://github.com/juliansteenbakker/flutter_ble_central/issues/128))
* `FlutterBleCentral.onPeripheralStateChanged` is renamed to `onCentralStateChanged`; this package is central mode ([#116](https://github.com/juliansteenbakker/flutter_ble_central/issues/116), [#128](https://github.com/juliansteenbakker/flutter_ble_central/issues/128))
* `FlutterBleCentral.isAdvertising` is removed. No platform ever implemented it, so it always returned `false` ([59c1f8d](https://github.com/juliansteenbakker/flutter_ble_central/commit/59c1f8da8131e12a6bacb97e429fe6c8b31454cc))
* **android:** a disabled adapter now reports `turnedOff` instead of `denied`, so `denied` means only that the permission was refused. Code that read `denied` as "Bluetooth is off" has to switch on `turnedOff` ([#108](https://github.com/juliansteenbakker/flutter_ble_central/issues/108))
* **macos:** the declared deployment target is 10.15, up from 10.14, which was below Flutter's own floor and could not be honoured ([#111](https://github.com/juliansteenbakker/flutter_ble_central/issues/111))
* `lib/src/models/enums/bluetooth_central_state.dart` is now `central_bluetooth_state.dart`. Only a direct `package:flutter_ble_central/src/...` import breaks; everything is still exported from `package:flutter_ble_central/flutter_ble_central.dart` ([#116](https://github.com/juliansteenbakker/flutter_ble_central/issues/116))

### Features

* add a gatt connection manager for android ([#113](https://github.com/juliansteenbakker/flutter_ble_central/issues/113)) ([b8220ca](https://github.com/juliansteenbakker/flutter_ble_central/commit/b8220cadb78a8495c619d843644c37d28aa2f443))
* **apple:** serve the gatt client half ([#118](https://github.com/juliansteenbakker/flutter_ble_central/issues/118)) ([3fd7820](https://github.com/juliansteenbakker/flutter_ble_central/commit/3fd7820d20d87ef2e848e0491bb01d0d49bb0f08))
* **windows:** serve the gatt client half ([#117](https://github.com/juliansteenbakker/flutter_ble_central/issues/117)) ([6fd19e8](https://github.com/juliansteenbakker/flutter_ble_central/commit/6fd19e8d8294dcbf1ba93617622e9f7c83d4c6b8))
* rename the state enums so the two packages stop colliding ([#116](https://github.com/juliansteenbakker/flutter_ble_central/issues/116)) ([dfcd675](https://github.com/juliansteenbakker/flutter_ble_central/commit/dfcd67571207a0ce87b43913657a9b1fafacb34e))
* keep the old state names as deprecated aliases ([#128](https://github.com/juliansteenbakker/flutter_ble_central/issues/128)) ([6126f96](https://github.com/juliansteenbakker/flutter_ble_central/commit/6126f9692ef6445968ecd70654124a2d115623ac))
* remove isAdvertising, it was never implemented natively ([59c1f8d](https://github.com/juliansteenbakker/flutter_ble_central/commit/59c1f8da8131e12a6bacb97e429fe6c8b31454cc))
* add an interop harness that runs every call across two devices ([#120](https://github.com/juliansteenbakker/flutter_ble_central/issues/120)) ([728a7cb](https://github.com/juliansteenbakker/flutter_ble_central/commit/728a7cb7ebb56fc43ce105bbeaedb6fcfb0e7f9e))
* rebuild the example app and add pong over the gatt link ([#122](https://github.com/juliansteenbakker/flutter_ble_central/issues/122)) ([4e34ce5](https://github.com/juliansteenbakker/flutter_ble_central/commit/4e34ce55512781c1746b7c53f41be3db61c233d8))


### Bug Fixes

* **android:** report the disconnect instead of closing the client first ([#123](https://github.com/juliansteenbakker/flutter_ble_central/issues/123)) ([f71904e](https://github.com/juliansteenbakker/flutter_ble_central/commit/f71904e5d3763d0b8f9c80e15403486f67e243c6))
* report a disabled adapter as TurnedOff instead of Denied ([#108](https://github.com/juliansteenbakker/flutter_ble_central/issues/108)) ([8050f25](https://github.com/juliansteenbakker/flutter_ble_central/commit/8050f25c67b9029477e9b31165dbb577450cfbf6))
* drop the misleading wire value from FlutterBleCentralState ([#107](https://github.com/juliansteenbakker/flutter_ble_central/issues/107)) ([b936908](https://github.com/juliansteenbakker/flutter_ble_central/commit/b9369087c00571975d98a094a1d5b314906d731a))
* darwin callback queue, parse scan results off main thread ([#98](https://github.com/juliansteenbakker/flutter_ble_central/issues/98)) ([383a747](https://github.com/juliansteenbakker/flutter_ble_central/commit/383a74755a348121dd2501152fb289b0cb24fa4e))
* raise the macos deployment target to 10.15 ([#111](https://github.com/juliansteenbakker/flutter_ble_central/issues/111)) ([0b799ff](https://github.com/juliansteenbakker/flutter_ble_central/commit/0b799ff47d92edbb7712cf8123556b2356e2ebfb))
* correct the windows state reporting and plugin teardown ([#112](https://github.com/juliansteenbakker/flutter_ble_central/issues/112)) ([dd22813](https://github.com/juliansteenbakker/flutter_ble_central/commit/dd228131c5f6acb9aeb5b0174643c4f2cdc10434))
* **windows:** connect, scan uuids, and adapter queries against a real peripheral ([#121](https://github.com/juliansteenbakker/flutter_ble_central/issues/121)) ([5e6bfec](https://github.com/juliansteenbakker/flutter_ble_central/commit/5e6bfec67d1476aa72751bcd0a941455c7f6ae40))
* **windows:** report the advertisement and scan response as one scan result ([#124](https://github.com/juliansteenbakker/flutter_ble_central/issues/124)) ([eb0b97b](https://github.com/juliansteenbakker/flutter_ble_central/commit/eb0b97b66c8f7aa8fe17ef3ae04e814532b56664))
* return the converted map from Uint8ListMapStringConverter.toJson ([#106](https://github.com/juliansteenbakker/flutter_ble_central/issues/106)) ([057798e](https://github.com/juliansteenbakker/flutter_ble_central/commit/057798ed7925d1237dcc52b9124b053bd83b8ec3))
* **example:** defer link meter reports made while the tree is locked ([#125](https://github.com/juliansteenbakker/flutter_ble_central/issues/125)) ([cab1a11](https://github.com/juliansteenbakker/flutter_ble_central/commit/cab1a11b226b440d7422b8b2283f829de349c094))
* remove jetifier from example app, it fails the android build ([6340e7b](https://github.com/juliansteenbakker/flutter_ble_central/commit/6340e7b160c23cbe17a33c524fd66b2a2d0177e4))

## 0.3.3
- [Darwin] Fixed `CBCentralManager.authorization` macOS 10.15 availability guard
- [macOS] Removed CocoaPods integration from example app, migrated to Swift Package Manager
- [Darwin] Scan results are now parsed on CoreBluetooth's own callback queue instead of the main thread, so scan throughput no longer depends on how busy the Flutter UI is

## 0.3.2
- [Windows] Fixed crash when Bluetooth adapter is not present or Bluetooth is disabled
- [Windows] Added comprehensive exception handling throughout the plugin to prevent crashes from WinRT API failures
- [Windows] Fixed potential crashes in scan result processing and state change handlers

## 0.3.1
- Added RSSI to `useLightweightScanResult`

## 0.3.0
- Added `isBluetoothOn` getter to check if Bluetooth is powered on
- Added `isSupported` getter to check if BLE is supported on the device
- Added `enableBluetooth()` method (Android/Windows, returns false on Apple platforms)
- Added `openBluetoothSettings()` method to open system Bluetooth settings
- Added `openAppSettings()` method to open app settings
- [Android] Added Bluetooth state change listener using BroadcastReceiver
- [Android] Added StateChangedHandler for streaming state changes to Flutter
- [Android] Added activity lifecycle callbacks to refresh state when app resumes
- [Darwin] Fixed StateChangedHandler event channel name (was incorrectly using "peripheral" instead of "central")
- [Darwin] Added `hasPermission()` support using CBCentralManager.authorization API (iOS 13.1+/macOS 10.15+)
- [Windows] Added Bluetooth state change event channel
- [Windows] Added `isSupported`, `isBluetoothOn`, `hasPermission`, `enableBluetooth` method handlers
- [Windows] Added `openBluetoothSettings()` and `openAppSettings()` methods
- [Example] Complete redesign with Material 3 UI
- [Example] Added permission request dialogs with platform-specific UI
- [Example] Added Bluetooth off dialog with enable functionality

## 0.2.1

- [Android] Add a refresh timer that restarts the scan after 4 minutes to prevent Android from changing the state of the scan to "opportunistic".

## 0.2.0

- Update permission system
- Merge iOS and macOS codebase
- Update permission system
- Add enableTimingStats to FlutterBleCentral and disable it by default


## 0.1.0

- [Android] Added useLightweightScanResult for android to improve fast scanning.
- Updated dependencies

## 0.0.8
- [macOS] Fixed build errors.

## 0.0.7
- [Android] Fixed requestPermission not working correctly.

## 0.0.6

Fixed windows search state

## 0.0.5

Various improvements

## 0.0.4

Added windows support.

## 0.0.3

Fixed macOS device address.

## 0.0.2

Fixed serviceUUIDs not being found on android and iOS.

## 0.0.1

Initial release with advertisement data support for Android, iOS and MacOS.
