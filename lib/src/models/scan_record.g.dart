// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'scan_record.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ScanRecord _$ScanRecordFromJson(Map<String, dynamic> json) => ScanRecord(
      advertiseFlags: json['advertiseFlags'] as int?,
      advertisingDataMap: const Uint8ListMapIntConverter()
          .fromJson(json['advertisingDataMap'] as Map<String, dynamic>?),
      bytes: const Uint8ListConverter().fromJson(json['bytes'] as List?),
      deviceName: json['deviceName'] as String?,
      manufacturerSpecificData: const Uint8ListMapIntConverter()
          .fromJson(json['manufacturerSpecificData'] as Map<String, dynamic>?),
      serviceData: const Uint8ListMapStringConverter()
          .fromJson(json['serviceData'] as Map<String, dynamic>?),
      serviceSolicitationUuids:
          (json['serviceSolicitationUuids'] as List<dynamic>?)
              ?.map((e) => e as String?)
              .toList(),
      serviceUuids: (json['serviceUuids'] as List<dynamic>?)
          ?.map((e) => e as String?)
          .toList(),
      txPowerLevel: json['txPowerLevel'] as int?,
    );

Map<String, dynamic> _$ScanRecordToJson(ScanRecord instance) =>
    <String, dynamic>{
      'advertiseFlags': instance.advertiseFlags,
      'advertisingDataMap':
          const Uint8ListMapIntConverter().toJson(instance.advertisingDataMap),
      'bytes': const Uint8ListConverter().toJson(instance.bytes),
      'deviceName': instance.deviceName,
      'manufacturerSpecificData': const Uint8ListMapIntConverter()
          .toJson(instance.manufacturerSpecificData),
      'serviceData':
          const Uint8ListMapStringConverter().toJson(instance.serviceData),
      'serviceSolicitationUuids': instance.serviceSolicitationUuids,
      'serviceUuids': instance.serviceUuids,
      'txPowerLevel': instance.txPowerLevel,
    };
