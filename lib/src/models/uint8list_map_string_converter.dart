import 'dart:typed_data';
import 'package:json_annotation/json_annotation.dart';

class Uint8ListMapStringConverter
    implements JsonConverter<Map<String, Uint8List>?, Map<String, dynamic>?> {
  const Uint8ListMapStringConverter();

  @override
  Map<String, Uint8List>? fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }

    final Map<String, Uint8List> map = {};
    for (var key in json.keys) {
      map[key] = Uint8List.fromList(json[key]!.cast<int>());
    }

    return map;
  }

  @override
  Map<String, List<int>>? toJson(Map<String, Uint8List>? object) {
    if (object == null) {
      return null;
    }
    final Map<String, dynamic> map = {};
    for (var key in object.keys) {
      map[key] = object[key]!.toList();
    }
    return object;
  }
}
