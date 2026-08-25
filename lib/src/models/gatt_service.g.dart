// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'gatt_service.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

GattService _$GattServiceFromJson(Map<String, dynamic> json) => GattService(
      uuid: json['uuid'] as String,
      isPrimary: json['isPrimary'] as bool,
      characteristics: (json['characteristics'] as List<dynamic>?)
          ?.map((e) =>
              GattCharacteristic.fromJson(const DeepMapConverter().fromJson(e)))
          .toList(),
    );

Map<String, dynamic> _$GattServiceToJson(GattService instance) =>
    <String, dynamic>{
      'uuid': instance.uuid,
      'isPrimary': instance.isPrimary,
      'characteristics': instance.characteristics,
    };
