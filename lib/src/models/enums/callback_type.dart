import 'package:json_annotation/json_annotation.dart';

enum CallbackType {
  @JsonValue(1)
  allMatches,
  @JsonValue(2)
  firstMatch,
  @JsonValue(4)
  matchLost,

  /// Added in Android UpsideDownCake
  @JsonValue(8)
  allMatchesAutoBatch,
}
