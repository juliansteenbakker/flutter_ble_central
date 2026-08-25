import 'dart:typed_data';
import 'package:json_annotation/json_annotation.dart';

/// Converter for `Map<String, Uint8List>` to/from JSON
class Uint8ListMapStringConverter
    implements JsonConverter<Map<String, Uint8List>?, Map<String, dynamic>?> {
  /// Creates a Uint8ListMapStringConverter
  const Uint8ListMapStringConverter();

  @override
  Map<String, Uint8List>? fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }

    final map = <String, Uint8List>{};
    for (final key in json.keys) {
      map[key] = Uint8List.fromList((json[key] as List).cast<int>());
    }

    return map;
  }

  @override
  Map<String, List<int>>? toJson(Map<String, Uint8List>? object) {
    if (object == null) {
      return null;
    }

    final map = <String, List<int>>{};
    for (final entry in object.entries) {
      map[entry.key] = entry.value.toList();
    }

    return map;
  }
}
