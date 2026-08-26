import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_ble_central/flutter_ble_central.dart';
import 'package:flutter_test/flutter_test.dart';

/// Collects the results [FlutterBleCentral.handleData] emits.
class _ListSink implements EventSink<ScanResult> {
  final results = <ScanResult>[];

  @override
  void add(ScanResult event) => results.add(event);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  void close() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(
    'dev.steenbakker.flutter_ble_central/method',
  );

  final ble = FlutterBleCentral();
  final calls = <MethodCall>[];
  Object? response;

  void mockChannel() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return response;
    });
  }

  setUp(() {
    calls.clear();
    response = null;
    ble.enableTimingStats = false;
    mockChannel();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('FlutterBleCentral', () {
    test('is a singleton', () {
      expect(FlutterBleCentral(), same(ble));
    });
  });

  // The Windows branches of start/stop are not covered here: they are selected
  // by dart:io Platform, which the test host decides.
  group('start', () {
    test(
      'sends the scan settings and the timing stats flag',
      () async {
        response = 8;
        ble.enableTimingStats = true;

        final state = await ble.start(
          scanSettings: ScanSettings(scanMode: ScanMode.scanModeLowLatency),
        );

        expect(calls.single.method, 'start');
        final arguments = calls.single.arguments as Map<Object?, Object?>;
        expect(arguments['scanMode'], 2);
        expect(arguments['enableTimingStats'], true);
        expect(state, CentralBluetoothState.ready);
      },
      skip: Platform.isWindows,
    );

    test(
      'defaults the settings when none are given',
      () async {
        response = 0;

        final state = await ble.start();

        final arguments = calls.single.arguments as Map<Object?, Object?>;
        expect(arguments['scanMode'], isNull);
        expect(arguments['enableTimingStats'], false);
        expect(state, CentralBluetoothState.granted);
      },
      skip: Platform.isWindows,
    );

    test(
      'maps a null response to unknown',
      () async {
        expect(await ble.start(), CentralBluetoothState.unknown);
      },
      skip: Platform.isWindows,
    );
  });

  group('stop', () {
    test(
      'maps the response to a state',
      () async {
        response = 5;
        expect(await ble.stop(), CentralBluetoothState.turnedOff);
        expect(calls.single.method, 'stop');
      },
      skip: Platform.isWindows,
    );

    test(
      'maps a null response to unknown',
      () async {
        expect(await ble.stop(), CentralBluetoothState.unknown);
      },
      skip: Platform.isWindows,
    );
  });

  group('boolean getters', () {
    test('return the native value', () async {
      response = true;
      expect(await ble.isSupported, true);
      expect(await ble.isBluetoothOn, true);
      expect(
        calls.map((c) => c.method),
        ['isSupported', 'isBluetoothOn'],
      );
    });

    test('fall back to false when the native side returns null', () async {
      expect(await ble.isSupported, false);
      expect(await ble.isBluetoothOn, false);
    });
  });

  group('enableBluetooth', () {
    test('forwards askUser', () async {
      response = true;

      expect(await ble.enableBluetooth(), true);
      expect(calls.single.method, 'enableBluetooth');
      expect(calls.single.arguments, true);

      await ble.enableBluetooth(askUser: false);
      expect(calls.last.arguments, false);
    });

    test('falls back to false', () async {
      expect(await ble.enableBluetooth(), false);
    });
  });

  group('permissions', () {
    test('map the response to a state', () async {
      response = 2;
      expect(
        await ble.requestPermission(),
        CentralBluetoothState.permanentlyDenied,
      );

      response = 1;
      expect(await ble.hasPermission(), CentralBluetoothState.denied);

      expect(
        calls.map((c) => c.method),
        ['requestPermission', 'hasPermission'],
      );
    });

    test('map a null response to unknown', () async {
      expect(await ble.requestPermission(), CentralBluetoothState.unknown);
      expect(await ble.hasPermission(), CentralBluetoothState.unknown);
    });
  });

  // These reach Android only, but the channel payload is built in Dart, so the
  // wire contract is worth pinning wherever the tests run.
  group('pairing', () {
    test('createBond and removeBond send the address', () async {
      await ble.createBond('AA:BB');
      await ble.removeBond('AA:BB');

      expect(calls.map((c) => c.method), ['createBond', 'removeBond']);
      expect(calls.first.arguments, {'address': 'AA:BB'});
    });

    // The states are Android's BOND_* constants rather than the enum's index,
    // so a value read as an index would be wrong by ten.
    test('getBondState maps the native constant', () async {
      response = 12;
      expect(await ble.getBondState('AA:BB'), BondState.bonded);

      response = 11;
      expect(await ble.getBondState('AA:BB'), BondState.bonding);

      response = null;
      expect(await ble.getBondState('AA:BB'), BondState.none);
    });

    test('the enum carries the native values', () {
      expect(BondState.none.value, 10);
      expect(BondState.bonding.value, 11);
      expect(BondState.bonded.value, 12);
    });
  });

  group('connection tuning', () {
    test('requestConnectionPriority sends the native value', () async {
      await ble.requestConnectionPriority(
        address: 'AA:BB',
        priority: ConnectionPriority.lowPower,
      );

      expect(calls.single.method, 'requestConnectionPriority');
      expect(calls.single.arguments, {'address': 'AA:BB', 'priority': 2});
    });

    test('readPhy maps both directions', () async {
      response = {'txPhy': 2, 'rxPhy': 3};

      final phy = await ble.readPhy('AA:BB');

      expect(phy.tx, GattPhy.le2M);
      expect(phy.rx, GattPhy.leCoded);
    });

    test('readPhy falls back to 1M when the platform says nothing', () async {
      final phy = await ble.readPhy('AA:BB');

      expect(phy.tx, GattPhy.le1M);
      expect(phy.rx, GattPhy.le1M);
    });

    test('setPreferredPhy sends the native values', () async {
      await ble.setPreferredPhy(
        address: 'AA:BB',
        txPhy: GattPhy.le2M,
        rxPhy: GattPhy.leCoded,
        phyOption: PhyOption.s8,
      );

      expect(calls.single.arguments, {
        'address': 'AA:BB',
        'txPhy': 2,
        'rxPhy': 3,
        'phyOptions': 2,
      });
    });

    test('setPreferredPhy defaults to no preferred coding', () async {
      await ble.setPreferredPhy(
        address: 'AA:BB',
        txPhy: GattPhy.le1M,
        rxPhy: GattPhy.le1M,
      );

      expect((calls.single.arguments as Map)['phyOptions'], 0);
    });
  });

  group('reliable write', () {
    test('the three calls send the address', () async {
      await ble.beginReliableWrite('AA:BB');
      await ble.executeReliableWrite('AA:BB');
      await ble.abortReliableWrite('AA:BB');

      expect(calls.map((c) => c.method), [
        'beginReliableWrite',
        'executeReliableWrite',
        'abortReliableWrite',
      ]);
      expect(calls.last.arguments, {'address': 'AA:BB'});
    });
  });

  group('event parsing', () {
    test('a connection state change', () {
      final event = ConnectionStateChange.fromPlatform({
        'address': 'AA:BB',
        'state': GattConnectionState.connected.index,
      });

      expect(event.address, 'AA:BB');
      expect(event.state, GattConnectionState.connected);
    });

    test('a connection state out of range falls back to disconnected', () {
      final event = ConnectionStateChange.fromPlatform({'state': 99});

      expect(event.state, GattConnectionState.disconnected);
      expect(event.address, '');
    });

    test('a characteristic value', () {
      final event = CharacteristicValue.fromPlatform({
        'address': 'AA:BB',
        'serviceUuid': 'abcd',
        'characteristicUuid': 'ef01',
        'value': Uint8List.fromList([1, 2, 3]),
      });

      expect(event.serviceUuid, 'abcd');
      expect(event.characteristicUuid, 'ef01');
      expect(event.value, [1, 2, 3]);
    });

    // Windows hands the bytes back as a plain list rather than a byte buffer.
    test('a characteristic value sent as a list', () {
      final event = CharacteristicValue.fromPlatform({
        'value': [1, 2, 3],
      });

      expect(event.value, isA<Uint8List>());
      expect(event.value, [1, 2, 3]);
    });

    test('a bond state change', () {
      final event = BondStateChange.fromPlatform({
        'address': 'AA:BB',
        'bondState': 12,
      });

      expect(event.address, 'AA:BB');
      expect(event.state, BondState.bonded);
    });
  });

  group('settings shortcuts', () {
    test('invoke their channel method', () async {
      await ble.openBluetoothSettings();
      await ble.openAppSettings();

      expect(
        calls.map((c) => c.method),
        ['openBluetoothSettings', 'openAppSettings'],
      );
    });
  });

  // The Windows plugin reports the manufacturer id separately and returns
  // plain booleans from start/stop, so it takes its own branches.
  group('on Windows', () {
    test(
      'start reports ready and maps an unsupported adapter',
      () async {
        expect(await ble.start(), CentralBluetoothState.ready);
        expect(calls.single.method, 'start');

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'unsupported');
        });

        expect(await ble.start(), CentralBluetoothState.unsupported);
      },
      skip: !Platform.isWindows,
    );

    test(
      'start reports turnedOff on any other platform error',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'error');
        });

        expect(await ble.start(), CentralBluetoothState.turnedOff);
      },
      skip: !Platform.isWindows,
    );

    test(
      'stop reports ready',
      () async {
        expect(await ble.stop(), CentralBluetoothState.ready);
        expect(calls.single.method, 'stop');
      },
      skip: !Platform.isWindows,
    );

    test(
      'handleData prepends the manufacturer id to the payload',
      () {
        final sink = _ListSink();

        ble.handleData(
          <Object?, Object?>{
            'address': 'AA:BB:CC:DD:EE:FF',
            'deviceName': 'Sensor',
            'manufacturerId': 76,
            'manufacturerSpecificData': <Object?>[1, 2, 3],
          },
          sink,
        );

        expect(sink.results.single.scanRecord?.manufacturerSpecificData, {
          76: Uint8List.fromList([1, 2, 3]),
        });
      },
      skip: !Platform.isWindows,
    );
  });

  group('handleData', () {
    final isApple = Platform.isIOS || Platform.isMacOS;

    test(
      'parses an Android scan result',
      () {
        final sink = _ListSink();

        ble.handleData(
          <Object?, Object?>{
            'device': <Object?, Object?>{'address': 'AA:BB:CC:DD:EE:FF'},
            'rssi': -70,
            'scanRecord': <Object?, Object?>{
              'deviceName': 'Sensor',
              'serviceUuids': <Object?>['abcd'],
            },
          },
          sink,
        );

        final result = sink.results.single;
        expect(result.device?.address, 'AA:BB:CC:DD:EE:FF');
        expect(result.rssi, -70);
        expect(result.scanRecord?.deviceName, 'Sensor');
      },
      skip: isApple || Platform.isWindows,
    );

    test(
      'splits the manufacturer id off the payload',
      () {
        final sink = _ListSink();

        ble.handleData(
          <Object?, Object?>{
            'address': 'AA:BB:CC:DD:EE:FF',
            'deviceName': 'Sensor',
            'rssi': -70,
            // Little endian id 0x004C (Apple), followed by the payload.
            'manufacturerSpecificData': <Object?>[0x4C, 0x00, 1, 2, 3],
            'serviceUuids': <Object?>['abcd'],
          },
          sink,
        );

        final record = sink.results.single.scanRecord;
        expect(record?.manufacturerSpecificData, {
          76: Uint8List.fromList([1, 2, 3]),
        });
        expect(record?.deviceName, 'Sensor');
        expect(record?.serviceUuids, ['abcd']);
        expect(sink.results.single.device?.address, 'AA:BB:CC:DD:EE:FF');
      },
      skip: !isApple,
    );

    test(
      'drops manufacturer data shorter than an id plus a byte',
      () {
        final sink = _ListSink();

        ble.handleData(
          <Object?, Object?>{
            'address': 'AA:BB',
            'manufacturerSpecificData': <Object?>[0x4C, 0x00],
          },
          sink,
        );

        final record = sink.results.single.scanRecord;
        expect(record?.manufacturerSpecificData, isNull);
      },
      skip: !isApple,
    );

    test(
      'defaults a missing address to an empty string',
      () {
        final sink = _ListSink();

        ble.handleData(<Object?, Object?>{'rssi': -70}, sink);

        expect(sink.results.single.device?.address, '');
      },
      skip: !isApple,
    );
  });
}
