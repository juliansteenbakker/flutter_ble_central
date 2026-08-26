// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'gatt_characteristic.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GattCharacteristic _$GattCharacteristicFromJson(Map<String, dynamic> json) =>
    GattCharacteristic(
      uuid: json['uuid'] as String,
      serviceUuid: json['serviceUuid'] as String,
      properties: GattCharacteristicProperties.fromJson(
          json['properties'] as Map<String, dynamic>),
      descriptors: (json['descriptors'] as List<dynamic>?)
          ?.map((e) => GattDescriptor.fromJson(e as Map<String, dynamic>))
          .toList(),
      value: const Uint8ListConverter().fromJson(json['value'] as List?),
    );

Map<String, dynamic> _$GattCharacteristicToJson(GattCharacteristic instance) =>
    <String, dynamic>{
      'uuid': instance.uuid,
      'serviceUuid': instance.serviceUuid,
      'properties': instance.properties,
      'descriptors': instance.descriptors,
      'value': const Uint8ListConverter().toJson(instance.value),
    };

GattCharacteristicProperties _$GattCharacteristicPropertiesFromJson(
        Map<String, dynamic> json) =>
    GattCharacteristicProperties(
      broadcast: json['broadcast'] as bool? ?? false,
      read: json['read'] as bool? ?? false,
      writeWithoutResponse: json['writeWithoutResponse'] as bool? ?? false,
      write: json['write'] as bool? ?? false,
      notify: json['notify'] as bool? ?? false,
      indicate: json['indicate'] as bool? ?? false,
      authenticatedSignedWrites:
          json['authenticatedSignedWrites'] as bool? ?? false,
      extendedProperties: json['extendedProperties'] as bool? ?? false,
    );

Map<String, dynamic> _$GattCharacteristicPropertiesToJson(
        GattCharacteristicProperties instance) =>
    <String, dynamic>{
      'broadcast': instance.broadcast,
      'read': instance.read,
      'writeWithoutResponse': instance.writeWithoutResponse,
      'write': instance.write,
      'notify': instance.notify,
      'indicate': instance.indicate,
      'authenticatedSignedWrites': instance.authenticatedSignedWrites,
      'extendedProperties': instance.extendedProperties,
    };
