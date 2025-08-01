import 'package:flutter_ble_central/src/models/bluetooth_device.dart';
import 'package:flutter_ble_central/src/models/scan_record.dart';
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

  final bool? connectable;

  final int? queue;

  ScanResult({
    this.device,
    this.eventType,
    this.primaryPhy,
    this.secondaryPhy,
    this.advertisingSid,
    this.txPower,
    this.rssi,
    this.periodicAdvertisingInterval,
    this.scanRecord,
    this.timestampNanos,
    this.connectable,
    this.queue,
  });

  factory ScanResult.fromJson(Map<String, dynamic> json) =>
      _$ScanResultFromJson(json);

  Map<String, dynamic> toJson() => _$ScanResultToJson(this);

  factory ScanResult.fromPlatform(Map<Object?, Object?> raw) {
    final map = deepCastMap(raw);
    return ScanResult.fromJson(map);
  }

  static Map<String, dynamic> deepCastMap(Map<Object?, Object?> raw) {
    return raw.map((key, value) {
      final String castKey = key.toString();

      if (value is Map<Object?, Object?>) {
        return MapEntry(castKey, deepCastMap(value));
      }

      if (value is Map) {
        // fallback for mixed key types
        return MapEntry(castKey, deepCastMap(Map<Object?, Object?>.from(value)));
      }

      if (value is List) {
        return MapEntry(castKey, value.map((e) {
          if (e is Map) {
            return deepCastMap(Map<Object?, Object?>.from(e));
          }
          return e;
        }).toList());
      }

      return MapEntry(castKey, value);
    });
  }


}
