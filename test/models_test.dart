import 'dart:typed_data';

import 'package:flutter_ble_central/flutter_ble_central.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BluetoothDevice', () {
    test('round trips', () {
      final device = BluetoothDevice(
        address: 'AA:BB:CC:DD:EE:FF',
        bondState: 12,
        name: 'Sensor',
        type: 2,
      );

      final json = device.toJson();
      expect(json['address'], 'AA:BB:CC:DD:EE:FF');

      final decoded = BluetoothDevice.fromJson(json);
      expect(decoded.address, device.address);
      expect(decoded.bondState, device.bondState);
      expect(decoded.name, device.name);
      expect(decoded.type, device.type);
    });
  });

  group('ScanRecord', () {
    test('round trips binary fields', () {
      final record = ScanRecord(
        advertiseFlags: 6,
        bytes: Uint8List.fromList([2, 1, 6]),
        deviceName: 'Sensor',
        manufacturerSpecificData: {
          76: Uint8List.fromList([1, 2, 3]),
        },
        serviceData: {
          '0000feaa-0000-1000-8000-00805f9b34fb': Uint8List.fromList([16]),
        },
        serviceUuids: const ['0000feaa-0000-1000-8000-00805f9b34fb'],
        txPowerLevel: -12,
      );

      final decoded = ScanRecord.fromJson(record.toJson());

      expect(decoded.advertiseFlags, 6);
      expect(decoded.bytes, record.bytes);
      expect(decoded.deviceName, 'Sensor');
      expect(decoded.manufacturerSpecificData, record.manufacturerSpecificData);
      expect(decoded.serviceData, record.serviceData);
      expect(decoded.serviceUuids, record.serviceUuids);
      expect(decoded.txPowerLevel, -12);
    });

    test('tolerates an empty record', () {
      final decoded = ScanRecord.fromJson(<String, dynamic>{});

      expect(decoded.deviceName, isNull);
      expect(decoded.manufacturerSpecificData, isNull);
      expect(decoded.serviceUuids, isNull);
    });
  });

  group('ScanSettings', () {
    // These numbers are the wire format shared with the Android side, so they
    // must not drift.
    test('encodes enums as their Android constants', () {
      final json = ScanSettings(
        scanMode: ScanMode.scanModeLowLatency,
        reportDelay: 0,
        phy: Phy.phyLeCoded,
        legacyMode: false,
        useLightweightScanResult: true,
      ).toJson();

      expect(json['scanMode'], 2);
      expect(json['phy'], 3);
      expect(json['reportDelay'], 0);
      expect(json['legacyMode'], false);
      expect(json['useLightweightScanResult'], true);
    });

    test('opportunistic scan mode encodes as -1', () {
      expect(
        ScanSettings(scanMode: ScanMode.scanModeOpportunistic)
            .toJson()['scanMode'],
        -1,
      );
    });

    test('round trips', () {
      final settings = ScanSettings(
        scanMode: ScanMode.scanModeBalanced,
        phy: Phy.phyLe2M,
      );

      final decoded = ScanSettings.fromJson(settings.toJson());

      expect(decoded.scanMode, ScanMode.scanModeBalanced);
      expect(decoded.phy, Phy.phyLe2M);
      expect(decoded.matchMode, isNull);
    });
  });

  group('ScanResult.deepCastMap', () {
    test('casts nested platform maps to String keys', () {
      final raw = <Object?, Object?>{
        'device': <Object?, Object?>{'address': 'AA:BB'},
        'scanRecord': <dynamic, dynamic>{
          'deviceName': 'Sensor',
          'serviceUuids': <dynamic>['abcd'],
        },
        'rssi': -60,
      };

      final map = ScanResult.deepCastMap(raw);

      expect(map['device'], isA<Map<String, dynamic>>());
      expect(map['scanRecord'], isA<Map<String, dynamic>>());
      final record = map['scanRecord']! as Map<String, dynamic>;
      expect(record['deviceName'], 'Sensor');
      expect(map['rssi'], -60);
    });

    test('casts maps nested inside lists', () {
      final map = ScanResult.deepCastMap(<Object?, Object?>{
        'items': <dynamic>[
          <dynamic, dynamic>{'a': 1},
        ],
      });

      final items = map['items'] as List<dynamic>;
      expect(items.single, isA<Map<String, dynamic>>());
    });

    test('stringifies non-String keys', () {
      final map = ScanResult.deepCastMap(<Object?, Object?>{76: 'value'});
      expect(map['76'], 'value');
    });
  });

  group('ScanResult', () {
    test('parses an Android scan result', () {
      final result = ScanResult.fromPlatform(<Object?, Object?>{
        'device': <Object?, Object?>{
          'address': 'AA:BB:CC:DD:EE:FF',
          'name': 'Sensor',
        },
        'rssi': -60,
        'connectable': true,
        'scanRecord': <Object?, Object?>{
          'deviceName': 'Sensor',
          'manufacturerSpecificData': <Object?, Object?>{
            '76': <dynamic>[1, 2],
          },
        },
      });

      expect(result.device?.address, 'AA:BB:CC:DD:EE:FF');
      expect(result.rssi, -60);
      expect(result.connectable, true);
      expect(
        result.scanRecord?.manufacturerSpecificData,
        {
          76: Uint8List.fromList([1, 2]),
        },
      );
    });
  });

  group('CentralState', () {
    // The state channel sends ordinals, not these codes; `code` is a separate
    // legacy mapping. Pinned here so it cannot drift silently.
    test('maps every state to its code', () {
      expect(CentralState.unknown.code, 10);
      expect(CentralState.unsupported.code, 11);
      expect(CentralState.unauthorized.code, 12);
      expect(CentralState.poweredOff.code, 13);
      expect(CentralState.idle.code, 14);
      expect(CentralState.advertising.code, 15);
      expect(CentralState.connected.code, 16);
    });

    test('codes are unique and cover every value', () {
      final codes = CentralState.values.map((s) => s.code).toSet();
      expect(codes, hasLength(CentralState.values.length));
    });
  });

  group('AndroidError', () {
    // Declared in Android SCAN_FAILED_* order, so the enum index is one lower
    // than the error code the native side publishes (code 1 is values[0]).
    test('is declared in Android scan failure order', () {
      expect(AndroidError.values, hasLength(6));
      expect(AndroidError.values.first, AndroidError.scanFailedAlreadyStarted);
      expect(
        AndroidError.values.last,
        AndroidError.scanFailedScanningTooFrequently,
      );
    });
  });
}
