// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bluetooth_device.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BluetoothDevice _$BluetoothDeviceFromJson(Map<String, dynamic> json) =>
    BluetoothDevice(
      address: json['address'] as String,
      bondState: json['bondState'] as int?,
      name: json['name'] as String?,
      type: json['type'] as int?,
    );

Map<String, dynamic> _$BluetoothDeviceToJson(BluetoothDevice instance) =>
    <String, dynamic>{
      'address': instance.address,
      'bondState': instance.bondState,
      'name': instance.name,
      'type': instance.type,
    };
