import 'package:json_annotation/json_annotation.dart';

/// Android BLE scan error codes
enum AndroidError {
  /// Scan failed because it was already started
  @JsonValue(1)
  scanFailedAlreadyStarted,

  /// Application registration failed
  @JsonValue(2)
  scanFailedApplicationRegistrationFailed,

  /// Internal error occurred
  @JsonValue(3)
  scanFailedInternalError,

  /// Feature is not supported
  @JsonValue(4)
  scanFailedFeatureUnsupported,

  /// Out of hardware resources
  @JsonValue(5)
  scanFailedOutOfHardwareResources,

  /// Scanning too frequently
  @JsonValue(6)
  scanFailedScanningTooFrequently,
}
