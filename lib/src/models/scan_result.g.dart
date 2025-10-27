// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'scan_result.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ScanResult _$ScanResultFromJson(Map<String, dynamic> json) => ScanResult(
      device: json['device'] == null
          ? null
          : BluetoothDevice.fromJson(json['device'] as Map<String, dynamic>),
      eventType: (json['eventType'] as num?)?.toInt(),
      primaryPhy: (json['primaryPhy'] as num?)?.toInt(),
      secondaryPhy: (json['secondaryPhy'] as num?)?.toInt(),
      advertisingSid: (json['advertisingSid'] as num?)?.toInt(),
      txPower: (json['txPower'] as num?)?.toInt(),
      rssi: (json['rssi'] as num?)?.toInt(),
      periodicAdvertisingInterval:
          (json['periodicAdvertisingInterval'] as num?)?.toInt(),
      scanRecord: json['scanRecord'] == null
          ? null
          : ScanRecord.fromJson(json['scanRecord'] as Map<String, dynamic>),
      timestampNanos: (json['timestampNanos'] as num?)?.toInt(),
      connectable: json['connectable'] as bool?,
      queue: (json['queue'] as num?)?.toInt(),
    );

Map<String, dynamic> _$ScanResultToJson(ScanResult instance) =>
    <String, dynamic>{
      'device': instance.device,
      'eventType': instance.eventType,
      'primaryPhy': instance.primaryPhy,
      'secondaryPhy': instance.secondaryPhy,
      'advertisingSid': instance.advertisingSid,
      'txPower': instance.txPower,
      'rssi': instance.rssi,
      'periodicAdvertisingInterval': instance.periodicAdvertisingInterval,
      'scanRecord': instance.scanRecord,
      'timestampNanos': instance.timestampNanos,
      'connectable': instance.connectable,
      'queue': instance.queue,
    };
