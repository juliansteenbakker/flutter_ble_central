import 'dart:typed_data';
import 'package:flutter_ble_central/src/models/uint8list_converter.dart';
import 'package:json_annotation/json_annotation.dart';

part 'gatt_descriptor.g.dart';

/// Represents a GATT descriptor
@JsonSerializable()
class GattDescriptor {
  /// Creates a GattDescriptor
  GattDescriptor({
    required this.uuid,
    required this.characteristicUuid,
    required this.serviceUuid,
    this.value,
  });

  /// Creates a GattDescriptor from JSON
  factory GattDescriptor.fromJson(Map<String, dynamic> json) =>
      _$GattDescriptorFromJson(json);

  /// The descriptor UUID
  final String uuid;

  /// The characteristic UUID this descriptor belongs to
  final String characteristicUuid;

  /// The service UUID
  final String serviceUuid;

  /// The current value of this descriptor
  @Uint8ListConverter()
  final Uint8List? value;

  /// Converts this GattDescriptor to JSON
  Map<String, dynamic> toJson() => _$GattDescriptorToJson(this);
}
