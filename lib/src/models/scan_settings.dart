import 'package:flutter_ble_central/src/models/enums/scan_mode.dart';

/// Model of the data to be advertised.
class ScanSettings {
  /// Android only
  ///
  /// Set advertise mode to control the advertising power and latency.
  /// Default: AdvertiseMode.ADVERTISE_MODE_LOW_LATENCY
  final ScanMode scanMode;

  ScanSettings({
    this.scanMode = ScanMode.scanModeLowLatency
  });
}
