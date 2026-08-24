# Security Policy

## Supported Versions

Only the latest released version of `flutter_ble_central` is supported with security
updates.

## Scope

This plugin is a Flutter wrapper around each platform's native BLE central API
(Android `BluetoothLeScanner`, Apple `CoreBluetooth`, Windows WinRT `Bluetooth*`).
Vulnerabilities in those operating-system APIs, in the Bluetooth stack, or in the
Bluetooth specification itself should be reported to the relevant platform vendor
rather than here.

Issues in this repository's Dart API or in its Android/Apple/Windows platform
channel code are in scope here. That includes anything where the plugin mishandles
untrusted data coming off the air — advertisement payloads, GATT responses, and
device names are all attacker-controlled input.

## Reporting a Vulnerability

If you discover a security vulnerability, please **do not** open a public GitHub issue. Instead, report it privately using [GitHub's private vulnerability reporting](https://github.com/juliansteenbakker/flutter_ble_central/security/advisories/new).

Please include as much detail as possible (affected platform, reproduction steps, potential impact) so the report can be triaged quickly.
