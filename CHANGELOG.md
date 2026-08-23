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
