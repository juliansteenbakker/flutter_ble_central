import 'package:json_annotation/json_annotation.dart';

/// Set match mode for Bluetooth LE scan filters hardware match.
enum MatchMode {
  /// In Aggressive mode, hw will determine a match sooner even with feeble signal strength
  /// and few number of sightings/match in a duration.
  @JsonValue(1)
  aggressive,

  /// For sticky mode, higher threshold of signal strength and sightings is required
  /// before reporting by hw.
  @JsonValue(2)
  sticky,
}
