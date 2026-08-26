import 'dart:typed_data';
import 'package:flutter_ble_central/src/models/gatt_descriptor.dart';
import 'package:flutter_ble_central/src/models/uint8list_converter.dart';
import 'package:json_annotation/json_annotation.dart';

part 'gatt_characteristic.g.dart';

/// Represents a GATT characteristic
@JsonSerializable()
class GattCharacteristic {
  /// Creates a GattCharacteristic
  GattCharacteristic({
    required this.uuid,
    required this.serviceUuid,
    required this.properties,
    this.descriptors,
    this.value,
  });

  /// Creates a GattCharacteristic from JSON
  factory GattCharacteristic.fromJson(Map<String, dynamic> json) =>
      _$GattCharacteristicFromJson(json);

  /// The characteristic UUID
  final String uuid;

  /// The service UUID this characteristic belongs to
  final String serviceUuid;

  /// The properties of this characteristic
  final GattCharacteristicProperties properties;

  /// The descriptors of this characteristic
  final List<GattDescriptor>? descriptors;

  /// The current value of this characteristic
  @Uint8ListConverter()
  final Uint8List? value;

  /// Converts this GattCharacteristic to JSON
  Map<String, dynamic> toJson() => _$GattCharacteristicToJson(this);
}

/// Properties of a GATT characteristic
@JsonSerializable()
class GattCharacteristicProperties {
  /// Creates GattCharacteristicProperties
  GattCharacteristicProperties({
    this.broadcast = false,
    this.read = false,
    this.writeWithoutResponse = false,
    this.write = false,
    this.notify = false,
    this.indicate = false,
    this.authenticatedSignedWrites = false,
    this.extendedProperties = false,
  });

  /// Creates GattCharacteristicProperties from JSON
  factory GattCharacteristicProperties.fromJson(Map<String, dynamic> json) =>
      _$GattCharacteristicPropertiesFromJson(json);

  /// Whether broadcast is supported
  final bool broadcast;

  /// Whether read is supported
  final bool read;

  /// Whether write without response is supported
  final bool writeWithoutResponse;

  /// Whether write is supported
  final bool write;

  /// Whether notify is supported
  final bool notify;

  /// Whether indicate is supported
  final bool indicate;

  /// Whether authenticated signed writes are supported
  final bool authenticatedSignedWrites;

  /// Whether extended properties are supported
  final bool extendedProperties;

  /// Converts this GattCharacteristicProperties to JSON
  Map<String, dynamic> toJson() => _$GattCharacteristicPropertiesToJson(this);
}
