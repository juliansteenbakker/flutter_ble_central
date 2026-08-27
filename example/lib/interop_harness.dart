// The central half of the interop harness.
//
// It is not a demo. It scans for the peripheral harness, runs every call the
// plugin serves against it, and reports each one on stdout as a `HARNESS|`
// line for `tool/interop_test.dart` to read. Run it with:
//
//     flutter run -d <device> -t lib/interop_harness.dart
//
// The other half is `example/lib/interop_harness.dart` in
// flutter_ble_peripheral, which has to be advertising before this starts.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ble_central/flutter_ble_central.dart';

/// The service the peripheral harness serves, and the only thing this connects
/// to. Kept in step with `harnessServiceUuid` on the peripheral side.
const harnessServiceUuid = 'bf27730d-860a-4e09-889c-2d8b6a9e0fe7';

/// Whether to run the pairing calls that a platform actually serves.
///
/// Off by default: pairing puts a system dialog in front of the person running
/// the harness and leaves a bond behind afterwards, neither of which belongs in
/// a run meant to be unattended. The calls a platform is expected to refuse are
/// still checked, since refusing costs nothing.
const runBondingCalls = bool.fromEnvironment('HARNESS_BONDING');

/// How long to wait for the peripheral to turn up in a scan.
const scanTimeout = Duration(seconds: 30);

/// How long any single call is given before it counts as hung.
const callTimeout = Duration(seconds: 20);

void main() => runApp(const InteropHarnessApp());

/// Names this platform the way the report does.
String get platformName {
  if (Platform.isAndroid) return 'android';
  if (Platform.isIOS) return 'ios';
  if (Platform.isMacOS) return 'macos';
  if (Platform.isWindows) return 'windows';
  if (Platform.isLinux) return 'linux';
  return 'unknown';
}

/// The calls this platform is documented not to serve, which are expected to
/// throw a `PlatformException` with code `unsupported`.
///
/// This is the README's support matrix written down, so a run that disagrees
/// with it is either a bug in the plugin or a stale README.
Set<String> get unsupportedHere {
  if (Platform.isAndroid) return const {};
  if (Platform.isIOS || Platform.isMacOS) {
    return const {
      'createBond',
      'removeBond',
      'getBondState',
      'requestConnectionPriority',
      'readPhy',
      'setPreferredPhy',
      'beginReliableWrite',
      'executeReliableWrite',
      'abortReliableWrite',
    };
  }
  if (Platform.isWindows) {
    return const {
      'readRssi',
      'readPhy',
      'setPreferredPhy',
      'requestConnectionPriority',
      'getBondState',
      'beginReliableWrite',
      'executeReliableWrite',
      'abortReliableWrite',
    };
  }
  return const {};
}

/// One line of the protocol the orchestrator reads.
void emit(String kind, List<String> fields) {
  // Stdout is the whole point of the harness: the orchestrator reads it.
  // ignore: avoid_print
  print('HARNESS|$kind|${fields.join('|')}');
}

/// How one check came out.
enum Outcome {
  /// It did what this platform says it does.
  pass,

  /// It did not.
  fail,

  /// Not run, and not a verdict either way.
  skip,

  /// Run for the record, with nothing asserted about the answer.
  info,
}

/// One check and what it came to.
class CheckResult {
  /// Records a finished check.
  CheckResult(this.name, this.outcome, this.detail);

  /// The call, or the step, being checked.
  final String name;

  /// How it came out.
  final Outcome outcome;

  /// What it returned, or why it failed.
  final String detail;
}

/// The central half of the harness.
class InteropHarnessApp extends StatefulWidget {
  /// Creates the harness app.
  const InteropHarnessApp({super.key});

  @override
  State<InteropHarnessApp> createState() => _InteropHarnessAppState();
}

class _InteropHarnessAppState extends State<InteropHarnessApp> {
  final _ble = FlutterBleCentral();
  final _results = <CheckResult>[];

  /// Values the peripheral notified, waited on by the round-trip checks.
  final _notified = StreamController<Uint8List>.broadcast();

  StreamSubscription<CharacteristicValue>? _valueSub;

  String? _address;
  late String _txUuid;
  late String _rxUuid;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  @override
  void dispose() {
    unawaited(_valueSub?.cancel());
    unawaited(_notified.close());
    super.dispose();
  }

  void _report(String name, Outcome outcome, String detail) {
    emit('CHECK', [name, outcome.name.toUpperCase(), detail]);
    if (mounted) {
      setState(() => _results.add(CheckResult(name, outcome, detail)));
    }
  }

  /// Runs [body] as one check, deciding pass or fail from whether this platform
  /// is supposed to serve [name] at all.
  ///
  /// A call the platform refuses by name passes when the refusal is exactly the
  /// documented one, and a call it serves passes when it answers.
  Future<void> _check(String name, Future<String> Function() body) async {
    final expectedUnsupported = unsupportedHere.contains(name);
    try {
      final detail = await body().timeout(callTimeout);
      _report(
        name,
        expectedUnsupported ? Outcome.fail : Outcome.pass,
        expectedUnsupported
            ? 'expected unsupported, but it answered: $detail'
            : detail,
      );
    } on TimeoutException {
      _report(name, Outcome.fail, 'timed out after ${callTimeout.inSeconds}s');
    } on PlatformException catch (error) {
      if (expectedUnsupported && error.code == 'unsupported') {
        _report(name, Outcome.pass, 'unsupported, as documented');
      } else if (expectedUnsupported) {
        _report(
          name,
          Outcome.fail,
          'expected code unsupported, got ${error.code}: ${error.message}',
        );
      } else {
        _report(name, Outcome.fail, '${error.code}: ${error.message}');
      }
    } on Object catch (error) {
      _report(name, Outcome.fail, '$error');
    }
  }

  /// Runs [body] for the record. Whatever it answers is reported, and a failure
  /// is not held against the run.
  Future<void> _observe(String name, Future<String> Function() body) async {
    try {
      _report(name, Outcome.info, await body().timeout(callTimeout));
    } on PlatformException catch (error) {
      _report(name, Outcome.info, '${error.code}: ${error.message}');
    } on Object catch (error) {
      _report(name, Outcome.info, '$error');
    }
  }

  Future<void> _run() async {
    emit('READY', [platformName]);
    try {
      if (!await _setUp()) return;
      final address = await _findPeripheral();
      if (address == null) return;
      _address = address;

      if (!await _connect(address)) return;
      if (!await _discover(address)) return;

      await _linkChecks(address);
      await _dataChecks(address);
      await _matrixChecks(address);
      await _tearDown(address);
    } on Object catch (error) {
      emit('FATAL', ['$error']);
    } finally {
      final passed = _results.where((r) => r.outcome == Outcome.pass).length;
      final failed = _results.where((r) => r.outcome == Outcome.fail).length;
      final skipped = _results.where((r) => r.outcome == Outcome.skip).length;
      emit('DONE', ['$passed', '$failed', '$skipped']);
    }
  }

  /// The calls that need no peripheral.
  Future<bool> _setUp() async {
    await _check('isSupported', () async {
      final supported = await _ble.isSupported;
      if (!supported) throw StateError('BLE is not supported here');
      return 'true';
    });

    await _check('requestPermission', () async {
      // The request answers before the system dialog is dismissed, so the first
      // run on a device has to wait for whoever is at it to allow Bluetooth.
      var state = await _ble.requestPermission();
      final deadline = DateTime.now().add(const Duration(seconds: 90));
      while (!_granted(state) && DateTime.now().isBefore(deadline)) {
        emit('WAITING', ['Allow Bluetooth on this device to continue']);
        await Future<void>.delayed(const Duration(seconds: 2));
        state = await _ble.hasPermission();
      }
      if (!_granted(state)) throw StateError('permission is ${state.name}');
      return state.name;
    });

    await _check('isBluetoothOn', () async {
      final on = await _ble.isBluetoothOn;
      if (!on) throw StateError('the adapter is off');
      return 'true';
    });

    final blocked = _results.any((r) => r.outcome == Outcome.fail);
    if (blocked) emit('FATAL', ['The adapter is not usable; nothing else ran']);
    return !blocked;
  }

  static bool _granted(CentralBluetoothState state) =>
      state == CentralBluetoothState.granted ||
      state == CentralBluetoothState.ready;

  /// Scans until the peripheral harness turns up, and answers its address.
  Future<String?> _findPeripheral() async {
    final found = Completer<String>();
    final subscription = _ble.onScanResult.listen((result) {
      if (found.isCompleted) return;
      final address = result.device?.address;
      if (address == null) return;
      final uuids = result.scanRecord?.serviceUuids ?? const <String?>[];
      final matches = uuids.any(
        (uuid) => uuid?.toLowerCase() == harnessServiceUuid,
      );
      if (matches) found.complete(address);
    });

    try {
      await _check('startScan', () async {
        final state = await _ble.start();
        if (state != CentralBluetoothState.ready &&
            state != CentralBluetoothState.granted) {
          throw StateError('scan did not start: ${state.name}');
        }
        return state.name;
      });

      final address = await found.future.timeout(
        scanTimeout,
        onTimeout: () => '',
      );
      if (address.isEmpty) {
        _report(
          'findPeripheral',
          Outcome.fail,
          'no peripheral advertising $harnessServiceUuid within '
              '${scanTimeout.inSeconds}s',
        );
        emit('FATAL', ['The peripheral harness was never seen']);
        return null;
      }
      _report('findPeripheral', Outcome.pass, address);

      await _check('stopScan', () async => (await _ble.stop()).name);
      return address;
    } finally {
      await subscription.cancel();
    }
  }

  Future<bool> _connect(String address) async {
    final connected = _ble.onConnectionStateChanged
        .where(
          (event) =>
              event.address == address &&
              event.state == GattConnectionState.connected,
        )
        .first;

    await _check('connect', () async {
      await _ble.connect(address: address);
      // connect answers as soon as the request is in on every platform, so the
      // link is up only when the stream says so.
      await connected.timeout(callTimeout);
      return 'connected';
    });

    if (_results.last.outcome == Outcome.fail) {
      emit('FATAL', ['Could not connect; nothing else ran']);
      return false;
    }

    await _check('getConnectionState', () async {
      final state = await _ble.getConnectionState(address);
      if (state != GattConnectionState.connected) {
        throw StateError('reported ${state.name} while connected');
      }
      return state.name;
    });
    return true;
  }

  Future<bool> _discover(String address) async {
    var services = const <GattService>[];

    await _check('discoverServices', () async {
      services = await _ble.discoverServices(address);
      if (services.isEmpty) throw StateError('no services');
      return '${services.length} services';
    });

    final service = services.firstWhereOrNull(
      (s) => s.uuid.toLowerCase() == harnessServiceUuid,
    );

    await _check('harnessService', () async {
      if (service == null) {
        throw StateError('$harnessServiceUuid is not among what it serves');
      }
      return '${(service.characteristics ?? []).length} characteristics';
    });
    if (service == null) {
      emit('FATAL', ['The harness service is missing; nothing else ran']);
      return false;
    }

    final characteristics = service.characteristics ?? const [];
    final tx = characteristics.firstWhereOrNull(
      (c) => c.properties.notify || c.properties.indicate,
    );
    final rx = characteristics.firstWhereOrNull(
      (c) => c.properties.write || c.properties.writeWithoutResponse,
    );

    await _check('txCharacteristic', () async {
      if (tx == null) throw StateError('nothing on the service notifies');
      return tx.uuid;
    });
    await _check('rxCharacteristic', () async {
      if (rx == null) throw StateError('nothing on the service accepts writes');
      return rx.uuid;
    });
    if (tx == null || rx == null) {
      emit('FATAL', ['No TX/RX pair; the data checks did not run']);
      return false;
    }

    _txUuid = tx.uuid;
    _rxUuid = rx.uuid;

    // Reported rather than asserted: which descriptors a peripheral exposes is
    // its own business, and the platforms differ on what they hand back.
    final descriptors = characteristics
        .expand((c) => c.descriptors ?? const <GattDescriptor>[])
        .map((d) => d.uuid)
        .toList();
    _report('descriptors', Outcome.info, descriptors.join(', '));
    return true;
  }

  /// What the link itself reports.
  Future<void> _linkChecks(String address) async {
    await _check('requestMtu', () async {
      final mtu = await _ble.requestMtu(address: address, mtu: 185);
      if (mtu < 23) throw StateError('$mtu is below the 23 byte minimum');
      return '$mtu';
    });

    await _check('readRssi', () async {
      final rssi = await _ble.readRssi(address);
      if (rssi >= 0 || rssi < -127) throw StateError('$rssi is not plausible');
      return '$rssi dBm';
    });
  }

  /// Subscribing, writing, and the round trip the peripheral echoes back.
  Future<void> _dataChecks(String address) async {
    final txUuid = _txUuid;
    final rxUuid = _rxUuid;

    _valueSub = _ble.onCharacteristicValueChanged.listen((event) {
      if (event.characteristicUuid.toLowerCase() != txUuid.toLowerCase()) {
        return;
      }
      if (!_notified.isClosed) _notified.add(event.value);
    });

    await _check('setCharacteristicNotification.enable', () async {
      await _ble.setCharacteristicNotification(
        address: address,
        serviceUuid: harnessServiceUuid,
        characteristicUuid: txUuid,
        enable: true,
      );
      return 'subscribed to $txUuid';
    });

    await _check('writeCharacteristic.withResponse', () async {
      return _roundTrip(
        address,
        rxUuid,
        Uint8List.fromList([0x01, 0x02, 0x03]),
        withoutResponse: false,
      );
    });

    await _check('writeCharacteristic.withoutResponse', () async {
      return _roundTrip(
        address,
        rxUuid,
        Uint8List.fromList([0x0a, 0x0b]),
        withoutResponse: true,
      );
    });

    await _observe('readCharacteristic', () async {
      final value = await _ble.readCharacteristic(
        address: address,
        serviceUuid: harnessServiceUuid,
        characteristicUuid: txUuid,
      );
      return '${value.length} bytes';
    });

    // The only descriptor a notifying characteristic is sure to have is the
    // client configuration one, and the platforms disagree about reading and
    // writing it by hand, so both are recorded rather than asserted.
    const clientConfigUuid = '00002902-0000-1000-8000-00805f9b34fb';
    await _observe('readDescriptor', () async {
      final value = await _ble.readDescriptor(
        address: address,
        serviceUuid: harnessServiceUuid,
        characteristicUuid: txUuid,
        descriptorUuid: clientConfigUuid,
      );
      return '${value.length} bytes';
    });
    await _observe('writeDescriptor', () async {
      await _ble.writeDescriptor(
        address: address,
        serviceUuid: harnessServiceUuid,
        characteristicUuid: txUuid,
        descriptorUuid: clientConfigUuid,
        value: Uint8List.fromList([0x01, 0x00]),
      );
      return 'written';
    });
  }

  /// Writes [value] and waits for the peripheral to echo it back on TX.
  ///
  /// One round trip proves the write arrived, the subscription is live, and the
  /// bytes survived both directions.
  Future<String> _roundTrip(
    String address,
    String rxUuid,
    Uint8List value, {
    required bool withoutResponse,
  }) async {
    final echo = _notified.stream.first;
    await _ble.writeCharacteristic(
      address: address,
      serviceUuid: harnessServiceUuid,
      characteristicUuid: rxUuid,
      value: value,
      withoutResponse: withoutResponse,
    );
    final received = await echo.timeout(callTimeout);
    if (!_sameBytes(received, value)) {
      throw StateError(
        'echoed ${_hex(received)} for ${_hex(value)}',
      );
    }
    return 'round trip of ${value.length} bytes';
  }

  /// The calls whose availability is what is being checked, rather than their
  /// answer.
  Future<void> _matrixChecks(String address) async {
    await _check('readPhy', () async {
      final phy = await _ble.readPhy(address);
      return 'tx ${phy.tx.name}, rx ${phy.rx.name}';
    });

    await _check('setPreferredPhy', () async {
      await _ble.setPreferredPhy(
        address: address,
        txPhy: GattPhy.le2M,
        rxPhy: GattPhy.le2M,
      );
      return 'asked for 2M';
    });

    await _check('requestConnectionPriority', () async {
      await _ble.requestConnectionPriority(
        address: address,
        priority: ConnectionPriority.balanced,
      );
      return 'balanced';
    });

    await _check('beginReliableWrite', () async {
      await _ble.beginReliableWrite(address);
      return 'begun';
    });
    await _check('abortReliableWrite', () async {
      await _ble.abortReliableWrite(address);
      return 'aborted';
    });
    // Only meaningful after a begin that took, so it is checked last and its
    // failure on a platform that never began is expected.
    await _check('executeReliableWrite', () async {
      await _ble.beginReliableWrite(address);
      await _ble.executeReliableWrite(address);
      return 'committed';
    });

    await _check('getBondState', () async {
      return (await _ble.getBondState(address)).name;
    });

    // Pairing is left alone unless it is asked for: it puts a dialog in front
    // of whoever runs this and leaves a bond behind. The platforms that are
    // supposed to refuse it are still checked, since refusing is free.
    final bondingRefused = unsupportedHere.contains('createBond');
    if (bondingRefused || runBondingCalls) {
      await _check('createBond', () async {
        await _ble.createBond(address);
        return 'requested';
      });
      await _check('removeBond', () async {
        await _ble.removeBond(address);
        return 'removed';
      });
    } else {
      const how = 'pass --dart-define=HARNESS_BONDING=true';
      _report('createBond', Outcome.skip, how);
      _report('removeBond', Outcome.skip, how);
    }
  }

  Future<void> _tearDown(String address) async {
    await _check('setCharacteristicNotification.disable', () async {
      await _ble.setCharacteristicNotification(
        address: address,
        serviceUuid: harnessServiceUuid,
        characteristicUuid: _txUuid,
        enable: false,
      );
      return 'unsubscribed';
    });

    final disconnected = _ble.onConnectionStateChanged
        .where(
          (event) =>
              event.address == address &&
              event.state == GattConnectionState.disconnected,
        )
        .first;

    await _check('disconnect', () async {
      await _ble.disconnect(address);
      await disconnected.timeout(callTimeout);
      return 'disconnected';
    });

    await _check('getConnectionState.afterDisconnect', () async {
      final state = await _ble.getConnectionState(address);
      if (state != GattConnectionState.disconnected) {
        throw StateError('reported ${state.name} after disconnecting');
      }
      return state.name;
    });
  }

  static bool _sameBytes(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static String _hex(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      home: Scaffold(
        appBar: AppBar(
          title: Text('Interop harness — $platformName'),
          bottom: _address == null
              ? null
              : PreferredSize(
                  preferredSize: const Size.fromHeight(20),
                  child: Text(_address!),
                ),
        ),
        body: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _results.length,
          itemBuilder: (context, index) {
            final result = _results[index];
            return ListTile(
              dense: true,
              leading: Icon(
                _iconFor(result.outcome),
                color: _colorFor(result.outcome),
              ),
              title: Text(result.name),
              subtitle: Text(result.detail),
            );
          },
        ),
      ),
    );
  }

  static IconData _iconFor(Outcome outcome) => switch (outcome) {
        Outcome.pass => Icons.check_circle,
        Outcome.fail => Icons.cancel,
        Outcome.skip => Icons.remove_circle_outline,
        Outcome.info => Icons.info_outline,
      };

  static Color _colorFor(Outcome outcome) => switch (outcome) {
        Outcome.pass => Colors.green,
        Outcome.fail => Colors.red,
        Outcome.skip => Colors.grey,
        Outcome.info => Colors.blue,
      };
}

extension _FirstWhereOrNull<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T element) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
