import 'package:json_annotation/json_annotation.dart';

/// Set the number of matches for Bluetooth LE scan filters hardware match.
/// Determines how many advertisements to match per filter, as this is scarce hw resource.
enum MatchNum {
  /// Match one advertisement per filter.
  @JsonValue(1)
  oneAdvertisement,

  /// Match few advertisement per filter, depends on current capability and
  /// availability of the resources in hw.
  @JsonValue(2)
  fewAdvertisement,

  /// Match as many advertisement per filter as hw could allow, depends on current
  /// capability and availability of the resources in hw.
  @JsonValue(3)
  maxAdvertisement,
}
