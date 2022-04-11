import 'dart:typed_data';

import 'package:flutter_ble_central/src/models/map_uint8list_converter.dart';
import 'package:flutter_ble_central/src/models/uint8list_converter.dart';
import 'package:flutter_ble_central/src/models/uint8list_map_string_converter.dart';
import 'package:json_annotation/json_annotation.dart';

part 'scan_record.g.dart';

@JsonSerializable()
class ScanRecord {
  final int? advertiseFlags;

  @Uint8ListMapIntConverter()
  final Map<int, Uint8List>? advertisingDataMap;

  @Uint8ListConverter()
  final Uint8List? bytes;

  final String? deviceName;

  @Uint8ListMapIntConverter()
  final Map<int, Uint8List>? manufacturerSpecificData;

  @Uint8ListMapStringConverter()
  final Map<String, Uint8List>? serviceData;

  final List<String?>? serviceSolicitationUuids;

  final List<String?>? serviceUuids;

  final int? txPowerLevel;

  ScanRecord({
    this.advertiseFlags,
    this.advertisingDataMap,
    this.bytes,
    this.deviceName,
    this.manufacturerSpecificData,
    this.serviceData,
    this.serviceSolicitationUuids,
    this.serviceUuids,
    this.txPowerLevel,
  });

  factory ScanRecord.fromJson(Map<String, dynamic> json) =>
      _$ScanRecordFromJson(json);

  Map<String, dynamic> toJson() => _$ScanRecordToJson(this);
}
