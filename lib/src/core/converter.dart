import 'package:json_annotation/json_annotation.dart';

/// Converts the loosely typed maps the platform channel hands back.
///
/// A map that crosses the channel arrives as `Map<Object?, Object?>`, nested
/// maps and lists included, so every level is rebuilt with String keys before
/// json_serializable sees it.
class DeepMapConverter implements JsonConverter<Map<String, dynamic>, Object?> {
  /// Creates the converter.
  const DeepMapConverter();

  @override
  Map<String, dynamic> fromJson(Object? json) {
    return _deepConvert(json) as Map<String, dynamic>;
  }

  @override
  Object? toJson(Map<String, dynamic> object) => object;

  dynamic _deepConvert(dynamic value) {
    if (value is Map) {
      return value.map(
        (key, val) => MapEntry(key.toString(), _deepConvert(val)),
      );
    } else if (value is List) {
      return value.map(_deepConvert).toList();
    }
    return value;
  }
}
