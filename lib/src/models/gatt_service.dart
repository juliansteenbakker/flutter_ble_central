import 'package:flutter_ble_central/src/core/converter.dart';
import 'package:flutter_ble_central/src/models/gatt_characteristic.dart';
import 'package:json_annotation/json_annotation.dart';

part 'gatt_service.g.dart';

/// Represents a GATT service
@JsonSerializable()
class GattService {
  /// Creates a GattService
  GattService({
    required this.uuid,
    required this.isPrimary,
    this.characteristics,
  });

  /// Creates a GattService from JSON
  @DeepMapConverter()
  factory GattService.fromJson(Map<String, dynamic> json) =>
      _$GattServiceFromJson(json);

  /// The service UUID
  final String uuid;

  /// Whether this is a primary service
  final bool isPrimary;

  /// The characteristics of this service
  @DeepMapConverter()
  final List<GattCharacteristic>? characteristics;

  /// Converts this GattService to JSON
  Map<String, dynamic> toJson() => _$GattServiceToJson(this);
}
