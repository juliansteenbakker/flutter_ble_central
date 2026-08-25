// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'gatt_descriptor.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GattDescriptor _$GattDescriptorFromJson(Map<String, dynamic> json) =>
    GattDescriptor(
      uuid: json['uuid'] as String,
      characteristicUuid: json['characteristicUuid'] as String,
      serviceUuid: json['serviceUuid'] as String,
      value: const Uint8ListConverter().fromJson(json['value'] as List?),
    );

Map<String, dynamic> _$GattDescriptorToJson(GattDescriptor instance) =>
    <String, dynamic>{
      'uuid': instance.uuid,
      'characteristicUuid': instance.characteristicUuid,
      'serviceUuid': instance.serviceUuid,
      'value': const Uint8ListConverter().toJson(instance.value),
    };
