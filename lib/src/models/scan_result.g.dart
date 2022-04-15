// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'scan_result.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ScanResult _$ScanResultFromJson(Map<String, dynamic> json) => ScanResult(
      device: json['device'] == null
          ? null
          : BluetoothDevice.fromJson(json['device'] as Map<String, dynamic>),
      eventType: json['eventType'] as int?,
      primaryPhy: json['primaryPhy'] as int?,
      secondaryPhy: json['secondaryPhy'] as int?,
      advertisingSid: json['advertisingSid'] as int?,
      txPower: json['txPower'] as int?,
      rssi: json['rssi'] as int?,
      periodicAdvertisingInterval: json['periodicAdvertisingInterval'] as int?,
      scanRecord: json['scanRecord'] == null
          ? null
          : ScanRecord.fromJson(json['scanRecord'] as Map<String, dynamic>),
      timestampNanos: json['timestampNanos'] as int?,
      connectable: json['connectable'] as bool?,
      queue: json['queue'] as int?,
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
