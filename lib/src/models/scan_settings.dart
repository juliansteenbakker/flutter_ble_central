import 'package:flutter_ble_central/src/models/enums/phy.dart';
import 'package:flutter_ble_central/src/models/enums/scan_mode.dart';
import 'package:json_annotation/json_annotation.dart';

part 'scan_settings.g.dart';

/// Model of the data to be advertised.
@JsonSerializable()
class ScanSettings {
  /// Android only
  ///
  /// Set advertise mode to control the advertising power and latency.
  final ScanMode? scanMode;

  /// Set report delay timestamp for Bluetooth LE scan. If set to 0, you will be notified of scan results immediately.
  /// If > 0, scan results are queued up and delivered after the requested delay or 5000 milliseconds (whichever is higher).
  /// Note scan results may be delivered sooner if the internal buffers fill up.
  final int? reportDelay;

  // TODO
  /// Set the number of matches for Bluetooth LE scan filters hardware match.
  final int? numOfMatches;

  /// Android Oreo (SDK >= 26) only
  /// Set whether only legacy advertisments should be returned in scan results.
  /// Legacy advertisements include advertisements as specified by the Bluetooth core specification 4.2 and below.
  /// This is true by default for compatibility with older apps.
  final bool? legacyMode;

  /// Android Oreo (SDK >= 26) only
  final Phy? phy;

  ScanSettings({
    this.scanMode,
    this.reportDelay,
    this.numOfMatches,
    this.legacyMode,
    this.phy,
  });

  factory ScanSettings.fromJson(Map<String, dynamic> json) =>
      _$ScanSettingsFromJson(json);

  Map<String, dynamic> toJson() => _$ScanSettingsToJson(this);
}
