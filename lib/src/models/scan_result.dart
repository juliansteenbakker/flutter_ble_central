import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_ble_central/src/models/bluetooth_device.dart';
import 'package:flutter_ble_central/src/models/scan_record.dart';
import 'package:flutter_ble_central/src/peripheral.dart';
import 'package:json_annotation/json_annotation.dart';

part 'scan_result.g.dart';

/// A scan result emitted by the scanning operation, containing [Peripheral] and [AdvertisementData].
@JsonSerializable()
class ScanResult {
  final BluetoothDevice? device;

  final int? eventType;

  final int? primaryPhy;

  final int? secondaryPhy;

  final int? advertisingSid;

  final int? txPower;

  /// Signal strength of the peripheral in dBm.
  final int? rssi;

  final int? periodicAdvertisingInterval;

  final ScanRecord? scanRecord;

  final int? timestampNanos;

  ScanResult(
      {this.device,
      this.eventType,
      this.primaryPhy,
      this.secondaryPhy,
      this.advertisingSid,
      this.txPower,
      this.rssi,
      this.periodicAdvertisingInterval,
      this.scanRecord,
      this.timestampNanos});

  factory ScanResult.fromJson(Map<String, dynamic> json) =>
      _$ScanResultFromJson(json);

  Map<String, dynamic> toJson() => _$ScanResultToJson(this);
}
