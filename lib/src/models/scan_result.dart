import 'package:flutter_ble_central/src/models/bluetooth_device.dart';
import 'package:flutter_ble_central/src/models/scan_record.dart';
import 'package:json_annotation/json_annotation.dart';

part 'scan_result.g.dart';

/// A scan result emitted by the scanning operation,
/// containing [BluetoothDevice] and [ScanRecord].
@JsonSerializable()
class ScanResult {
  /// Creates a ScanResult
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

  /// Creates a ScanResult from JSON
  factory ScanResult.fromJson(Map<String, dynamic> json) =>
      _$ScanResultFromJson(json);

  /// Creates a ScanResult from platform data
  factory ScanResult.fromPlatform(Map<Object?, Object?> raw) {
    final map = deepCastMap(raw);
    return ScanResult.fromJson(map);
  }

  /// The Bluetooth device
  final BluetoothDevice? device;

  /// The event type
  final int? eventType;

  /// The primary PHY
  final int? primaryPhy;

  /// The secondary PHY
  final int? secondaryPhy;

  /// The advertising SID
  final int? advertisingSid;

  /// The TX power
  final int? txPower;

  /// Signal strength of the peripheral in dBm.
  final int? rssi;

  /// The periodic advertising interval
  final int? periodicAdvertisingInterval;

  /// The scan record
  final ScanRecord? scanRecord;

  /// The timestamp in nanoseconds
  final int? timestampNanos;

  /// Whether the device is connectable
  final bool? connectable;

  /// Queue size
  final int? queue;

  /// Converts this ScanResult to JSON
  Map<String, dynamic> toJson() => _$ScanResultToJson(this);

  /// Deep casts a map to ensure correct types
  static Map<String, dynamic> deepCastMap(Map<Object?, Object?> raw) {
    return raw.map((key, value) {
      final castKey = key.toString();

      if (value is Map<Object?, Object?>) {
        return MapEntry(castKey, deepCastMap(value));
      }

      if (value is Map) {
        // fallback for mixed key types
        return MapEntry(
          castKey,
          deepCastMap(Map<Object?, Object?>.from(value)),
        );
      }

      if (value is List) {
        return MapEntry(
          castKey,
          value.map((e) {
            if (e is Map) {
              return deepCastMap(Map<Object?, Object?>.from(e));
            }
            return e;
          }).toList(),
        );
      }

      return MapEntry(castKey, value);
    });
  }
}
