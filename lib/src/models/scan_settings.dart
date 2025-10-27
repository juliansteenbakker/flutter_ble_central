import 'package:flutter_ble_central/src/models/enums/callback_type.dart';
import 'package:flutter_ble_central/src/models/enums/match_mode.dart';
import 'package:flutter_ble_central/src/models/enums/match_num.dart';
import 'package:flutter_ble_central/src/models/enums/phy.dart';
import 'package:flutter_ble_central/src/models/enums/scan_mode.dart';
import 'package:json_annotation/json_annotation.dart';

part 'scan_settings.g.dart';

/// A configuration model for controlling Bluetooth LE scan behavior on **Android only**.
///
/// Mirrors the Android [`ScanSettings`](https://developer.android.com/reference/android/bluetooth/le/ScanSettings)
/// API and exposes the most commonly used parameters for scanning performance,
/// power usage, and filtering behavior.
@JsonSerializable()
class ScanSettings {
  /// Specifies the scan mode to control the **power consumption** and **latency** of the BLE scan.
  ///
  /// A higher scan mode (e.g., `ScanMode.lowLatency`) results in faster scan results but consumes more power.
  final ScanMode? scanMode;

  /// Specifies the delay (in milliseconds) before scan results are reported.
  ///
  /// - `0`: results are delivered immediately.
  /// - `> 0`: results are queued and delivered after the requested delay or **5000 ms** (whichever is higher).
  ///
  /// Results may be delivered earlier if the internal buffer fills up.
  final int? reportDelay;

  /// **Android Marshmallow (SDK ≥ 23)**
  /// Specifies the callback type used for BLE scans.
  ///
  /// This determines whether the callback is triggered for all matches,
  /// first matches, or matches with lost devices.
  final CallbackType? callbackType;

  /// **Android Marshmallow (SDK ≥ 23)**
  /// Specifies the match mode for scan filters at the hardware level.
  ///
  /// Controls how aggressively the hardware matches BLE scan filters,
  /// impacting power consumption and result frequency.
  final MatchMode? matchMode;

  /// **Android Marshmallow (SDK ≥ 23)**
  /// Specifies how many advertisements to match per filter.
  ///
  /// Useful for controlling the number of scan results per filter and
  /// balancing between performance and precision.
  final MatchNum? numOfMatches;

  /// **Android Oreo (SDK ≥ 26)**
  /// Indicates whether only **legacy advertisements** (Bluetooth 4.2 and below)
  /// should be returned in scan results.
  ///
  /// Defaults to `true` for compatibility with older devices and apps.
  final bool? legacyMode;

  /// **Android Oreo (SDK ≥ 26)**
  /// Specifies the **Physical Layer (PHY)** to use during scanning.
  ///
  /// This is only used if [legacyMode] is set to `false`.
  /// Use `BluetoothAdapter.isLeCodedPhySupported` to check support for LE Coded PHY.
  ///
  /// Attempting to use an unsupported PHY will result in scan failure.
  final Phy? phy;

  /// Enables or disables **lightweight scan result mapping**.
  ///
  /// - `true`: Uses a minimal result map including only essential fields
  ///   (e.g., `address`, `manufacturerSpecificData`, `serviceUuids`).
  /// - `false` (default): Returns full scan result data.
  ///
  /// This can improve performance in cases where full result data is not required.
  final bool? useLightweightScanResult;

  /// Creates a new [ScanSettings] configuration.
  ScanSettings({
    this.scanMode,
    this.reportDelay,
    this.callbackType,
    this.matchMode,
    this.numOfMatches,
    this.legacyMode,
    this.phy,
    this.useLightweightScanResult,
  });

  /// Creates a [ScanSettings] instance from a JSON map.
  factory ScanSettings.fromJson(Map<String, dynamic> json) =>
      _$ScanSettingsFromJson(json);

  /// Converts this [ScanSettings] instance to a JSON map.
  Map<String, dynamic> toJson() => _$ScanSettingsToJson(this);
}
