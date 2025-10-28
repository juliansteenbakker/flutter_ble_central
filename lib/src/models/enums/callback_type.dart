import 'package:json_annotation/json_annotation.dart';

/// BLE scan callback type
enum CallbackType {
  /// Callback for all matches
  @JsonValue(1)
  allMatches,

  /// Callback for first match only
  @JsonValue(2)
  firstMatch,

  /// Callback when match is lost
  @JsonValue(4)
  matchLost,

  /// Added in Android UpsideDownCake
  @JsonValue(8)
  allMatchesAutoBatch,
}
