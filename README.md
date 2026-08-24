[![pub package](https://img.shields.io/pub/v/flutter_ble_central?include_prereleases)](https://pub.dev/packages/flutter_ble_central)
[![CI](https://github.com/juliansteenbakker/flutter_ble_central/actions/workflows/ci.yml/badge.svg?branch=develop)](https://github.com/juliansteenbakker/flutter_ble_central/actions/workflows/ci.yml)
[![style: very good analysis](https://img.shields.io/badge/style-very_good_analysis-B22C89.svg)](https://pub.dev/packages/very_good_analysis)
[![GitHub Sponsors](https://img.shields.io/github/sponsors/juliansteenbakker?label=want%20support%3F%20sponsor%20me%20and%20I%27ll%20contact%20you%21)](https://github.com/sponsors/juliansteenbakker)

# flutter_ble_central

A Flutter package for scanning BLE data in central mode.

## Getting Started

This project is a starting point for a Flutter
[plug-in package](https://flutter.dev/developing-packages/),
a specialized package that includes platform-specific implementation code for
Android and/or iOS.

For help getting started with Flutter, view our
[online documentation](https://flutter.dev/docs), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Permissions

| Situation                            | previouslyRequested | previouslyGranted | rationale | Result              |
|--------------------------------------|---------------------|-------------------|-----------|---------------------|
| First time                           | false               | false             | false     | `Denied`            |
| User denies (no “don’t ask again”)   | true                | false             | true      | `Denied`            |
| User denies (with “don’t ask again”) | true                | false             | false     | `PermanentlyDenied` |
| User grants then revokes in settings | true/false          | true              | false     | `Denied`            |
| Already granted                      | true/false          | true              | n/a       | `Granted`           |


| Action                       | FlutterBleCentral       | FlutterBlePeripheral                   |
|------------------------------|-------------------------|----------------------------------------|
| Scanning for devices         | ✅ Yes                   | ❌ No                                   |
| Advertising                  | ❌ No                    | ✅ Yes                                  |
| Connecting to other devices  | ✅ Yes                   | ❌ No (it accepts connections)          |
| Hosting GATT services        | ❌ No                    | ✅ Yes                                  |
| Accessing GATT services      | ✅ Yes                   | ❌ No                                   |
| **Reading characteristics**  | ✅ Yes (from peripheral) | ❌ No (it provides data if read)        |
| **Writing characteristics**  | ✅ Yes (to peripheral)   | ❌ No (it receives writes from central) |
| Subscribing to notifications | ✅ Yes                   | ❌ No (it sends notifications)          |
****

