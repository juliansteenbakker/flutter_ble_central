import 'dart:typed_data';

import 'package:flutter_ble_central/src/models/map_uint8list_converter.dart';
import 'package:flutter_ble_central/src/models/uint8list_converter.dart';
import 'package:flutter_ble_central/src/models/uint8list_map_string_converter.dart';
import 'package:json_annotation/json_annotation.dart';

part 'scan_record.g.dart';

/// Represents a BLE scan record
@JsonSerializable()
class ScanRecord {
  /// Creates a ScanRecord
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

  /// Creates a ScanRecord from JSON
  factory ScanRecord.fromJson(Map<String, dynamic> json) =>
      _$ScanRecordFromJson(json);

  /// The advertise flags
  final int? advertiseFlags;

  /// The advertising data map
  @Uint8ListMapIntConverter()
  final Map<int, Uint8List>? advertisingDataMap;

  /// The raw bytes of the scan record
  @Uint8ListConverter()
  final Uint8List? bytes;

  /// The device name
  final String? deviceName;

  /// Manufacturer specific data
  @Uint8ListMapIntConverter()
  final Map<int, Uint8List>? manufacturerSpecificData;

  /// Service data
  @Uint8ListMapStringConverter()
  final Map<String, Uint8List>? serviceData;

  /// Service solicitation UUIDs
  final List<String?>? serviceSolicitationUuids;

  /// Service UUIDs
  final List<String?>? serviceUuids;

  /// The TX power level
  final int? txPowerLevel;

  /// Converts this ScanRecord to JSON
  Map<String, dynamic> toJson() => _$ScanRecordToJson(this);
}
