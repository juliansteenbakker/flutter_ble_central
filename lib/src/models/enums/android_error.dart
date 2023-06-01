import 'package:json_annotation/json_annotation.dart';

enum AndroidError {
  @JsonValue(1)
  scanFailedAlreadyStarted,
  @JsonValue(2)
  scanFailedApplicationRegistrationFailed,
  @JsonValue(3)
  scanFailedInternalError,
  @JsonValue(4)
  scanFailedFeatureUnsupported,
  @JsonValue(5)
  scanFailedOutOfHardwareResources,
  @JsonValue(6)
  scanFailedScanningTooFrequently
}
