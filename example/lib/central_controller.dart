/*
 * Copyright (c) 2026. Julian Steenbakker.
 * All rights reserved. Use of this source code is governed by a
 * BSD-style license that can be found in the LICENSE file.
 */

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ble_central/flutter_ble_central.dart';
import 'package:flutter_ble_central_example/shell/shell.dart';

/// The service the flutter_ble_peripheral example serves.
const peripheralServiceUuid = 'bf27730d-860a-4e09-889c-2d8b6a9e0fe7';

/// The characteristic that peripheral notifies on, exported there as
/// `defaultTxCharacteristicUuid`. It is the Nordic UART Service TX.
const peripheralTxUuid = '6e400003-b5a3-f393-e0a9-e50e24dcca9e';

/// The characteristic that peripheral accepts writes on, exported there as
/// `defaultRxCharacteristicUuid`. It is the Nordic UART Service RX.
const peripheralRxUuid = '6e400002-b5a3-f393-e0a9-e50e24dcca9e';

/// Something worth telling the user about, shown as a snack bar.
typedef Notice = ({String message, bool isError});

/// One payload that crossed the link.
typedef Packet = ({Uint8List bytes, PacketDirection direction, DateTime at});

/// Drives `FlutterBleCentral` and holds everything the pages read.
///
/// The pages are widgets over this: they call its methods and rebuild when it
/// notifies. Every plugin call goes through [_call], so a call the platform
/// does not serve reports that rather than throwing into the void.
final class CentralController extends ChangeNotifier implements RadioAccess {
  /// Creates a controller and starts listening to the plugin's streams.
  CentralController() {
    _ble.enableTimingStats = true;
    _subscriptions.addAll([
      _ble.onScanResult.listen(_onScanResult),
      _ble.onCentralStateChanged.listen(_onAdapterState),
      _ble.onConnectionStateChanged.listen(_onConnectionState),
      _ble.onCharacteristicValueChanged.listen(_onCharacteristicValue),
      _ble.onBondStateChanged.listen(_onBondState),
      ?_ble.onScanError?.listen(_onScanError),
    ]);
  }

  final _ble = FlutterBleCentral();
  final _subscriptions = <StreamSubscription<void>>[];

  /// What the status rail plots.
  final telemetry = LinkTelemetry();

  /// The most recent thing worth saying. The app shows it and clears it.
  final notice = ValueNotifier<Notice?>(null);

  final _devices = <String, ScanResult>{};

  // Scanning ---------------------------------------------------------------

  /// The settings the next scan starts with. Editable on the Setup page, and
  /// ignored by every platform except Android.
  ScanSettings get scanSettings => _scanSettings;
  ScanSettings _scanSettings = ScanSettings();
  set scanSettings(ScanSettings settings) {
    _scanSettings = settings;
    notifyListeners();
  }

  /// Whether the device list hides everything not serving
  /// [peripheralServiceUuid].
  bool get onlyPeripheralExample => _onlyPeripheralExample;
  bool _onlyPeripheralExample = false;
  set onlyPeripheralExample(bool only) {
    _onlyPeripheralExample = only;
    notifyListeners();
  }

  /// Whether a scan is running.
  bool get isScanning => _isScanning;
  bool _isScanning = false;

  /// Advertisements seen since the scan started, which is not the same as the
  /// number of devices: a device advertises many times.
  int get packetsSeen => _packetsSeen;
  int _packetsSeen = 0;

  /// The adapter's own state machine.
  CentralState get adapterState => _adapterState;
  CentralState _adapterState = CentralState.unknown;

  /// What the device list shows: the filter applied, strongest first.
  ///
  /// Sorted on read rather than on arrival, since every advertisement from a
  /// device already in the list changes its RSSI and so its place.
  List<ScanResult> get devices {
    final visible = _devices.values.where((result) {
      if (!_onlyPeripheralExample) return true;
      final uuids = result.scanRecord?.serviceUuids ?? const [];
      return uuids.any((uuid) => uuid?.toLowerCase() == peripheralServiceUuid);
    }).toList();
    return visible..sort((a, b) => (b.rssi ?? -999).compareTo(a.rssi ?? -999));
  }

  /// How many devices have been seen, before the filter.
  int get devicesSeen => _devices.length;

  // The link ---------------------------------------------------------------

  /// The peripheral this app is connected to, or null.
  String? get address => _address;
  String? _address;

  /// The name that peripheral advertised, if it advertised one.
  String? get peerName => _peerName;
  String? _peerName;

  /// Where the connection is in its state machine.
  GattConnectionState get connectionState => _connectionState;
  GattConnectionState _connectionState = GattConnectionState.disconnected;

  /// Whether there is a link to talk over.
  bool get isConnected => _connectionState == GattConnectionState.connected;

  /// What the peripheral serves, once discovery has run.
  List<GattService> get services => _services;
  List<GattService> _services = const [];

  /// The characteristic this app subscribes to.
  GattCharacteristic? get tx => _tx;
  GattCharacteristic? _tx;

  /// The characteristic this app writes to.
  GattCharacteristic? get rx => _rx;
  GattCharacteristic? _rx;

  /// The negotiated MTU, once it has been asked for.
  int? get mtu => _mtu;
  int? _mtu;

  /// The signal strength of the link, once it has been read.
  int? get linkRssi => _linkRssi;
  int? _linkRssi;

  /// The bond with the connected peripheral, once it has been read.
  BondState? get bondState => _bondState;
  BondState? _bondState;

  /// What has crossed the link, newest first.
  List<Packet> get traffic => List.unmodifiable(_traffic);
  final _traffic = <Packet>[];

  /// Called for every payload the peripheral notifies, so the game can read
  /// the link without the Data page being open.
  void Function(Uint8List bytes)? onInbound;

  /// Whether a game is running over the link.
  ///
  /// A game sends twenty packets a second in each direction. Logging each one
  /// would fill the traffic log with paddle positions and rebuild the app on
  /// every frame, so while this is set the packets are counted on the meter
  /// and nothing else.
  bool isGameRunning = false;

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    telemetry.dispose();
    notice.dispose();
    super.dispose();
  }

  // Streams ----------------------------------------------------------------

  void _onScanResult(ScanResult result) {
    _packetsSeen++;
    telemetry.count(PacketDirection.inbound);
    if (result.device?.address case final address?) {
      _devices[address] = result;
      if (address == _address) _reportLinkQuality(result.rssi);
    }
    if (_isScanning) notifyListeners();
  }

  void _onScanError(int code) {
    _say('Scan failed: ${AndroidError.values[code].name}', isError: true);
  }

  void _onAdapterState(CentralState state) {
    _adapterState = state;
    notifyListeners();
  }

  void _onConnectionState(ConnectionStateChange event) {
    if (event.address != _address) return;
    _connectionState = event.state;
    if (event.state == GattConnectionState.disconnected) {
      _forgetLink();
      _say('Disconnected');
    }
    notifyListeners();
  }

  void _onCharacteristicValue(CharacteristicValue event) {
    if (event.characteristicUuid != _tx?.uuid) return;
    telemetry.count(PacketDirection.inbound);
    onInbound?.call(event.value);
    if (isGameRunning) return;
    _record(event.value, PacketDirection.inbound);
    notifyListeners();
  }

  void _onBondState(BondStateChange event) {
    if (event.address != _address) return;
    _bondState = event.state;
    _say('Bond: ${event.state.name}');
    notifyListeners();
  }

  // Doing things -----------------------------------------------------------

  /// Starts scanning with [scanSettings].
  Future<void> startScan() async {
    final state = await _ble.start(scanSettings: _scanSettings);
    if (!state.access.isUsable) {
      _say('Cannot scan: ${state.access.label}', isError: true);
      return;
    }
    _devices.clear();
    _packetsSeen = 0;
    _isScanning = true;
    telemetry.report(
      grade: SignalGrade.fair,
      caption: 'scanning',
      level: 0.2,
    );
    notifyListeners();
  }

  /// Stops scanning. Safe to call when no scan is running.
  Future<void> stopScan() async {
    await _ble.stop();
    _isScanning = false;
    if (!isConnected) telemetry.clear();
    notifyListeners();
  }

  /// Connects to [address], discovers what it serves and subscribes to its
  /// notifying characteristic.
  ///
  /// This is the whole handshake in one place: `connect` only puts the request
  /// in, the link is up when the connection stream says so, and discovery has
  /// to run before a read or a write on every platform except Android.
  Future<void> connect(String address) async {
    if (_isScanning) await stopScan();

    _address = address;
    _peerName = _devices[address]?.scanRecord?.deviceName;
    _connectionState = GattConnectionState.connecting;
    telemetry.report(grade: SignalGrade.fair, caption: 'connecting', level: .4);
    notifyListeners();

    try {
      await _ble.connect(address: address);
      await _ble.onConnectionStateChanged
          .where(
            (event) =>
                event.address == address &&
                event.state == GattConnectionState.connected,
          )
          .first
          .timeout(const Duration(seconds: 15));

      _connectionState = GattConnectionState.connected;
      _services = await _ble.discoverServices(address);

      final service = _services.firstWhereOrNull(
        (service) => service.uuid.toLowerCase() == peripheralServiceUuid,
      );
      if (service == null) {
        _say('That peripheral does not serve the example service');
      } else {
        await _adoptTxRx(address, service);
      }
      _reportLinkQuality(_devices[address]?.rssi);
      notifyListeners();
    } on TimeoutException {
      _say('Timed out connecting to $address', isError: true);
      await disconnect();
    } on PlatformException catch (error) {
      _say('Connect failed: ${error.message}', isError: true);
      await disconnect();
    }
  }

  /// Finds the TX/RX pair on [service] and subscribes to TX.
  ///
  /// The uuids are tried first and the properties second, so a peripheral
  /// serving its own layout under the same service still works.
  Future<void> _adoptTxRx(String address, GattService service) async {
    final characteristics = service.characteristics ?? const [];
    _tx = _pick(
      characteristics,
      peripheralTxUuid,
      (p) => p.notify || p.indicate,
    );
    _rx = _pick(
      characteristics,
      peripheralRxUuid,
      (p) => p.write || p.writeWithoutResponse,
    );

    if (_tx case final tx?) {
      await _ble.setCharacteristicNotification(
        address: address,
        serviceUuid: service.uuid,
        characteristicUuid: tx.uuid,
        enable: true,
      );
      _say('Connected and subscribed');
    } else {
      _say('No notifying characteristic to subscribe to', isError: true);
    }
  }

  GattCharacteristic? _pick(
    List<GattCharacteristic> characteristics,
    String uuid,
    bool Function(GattCharacteristicProperties) matches,
  ) {
    return characteristics.firstWhereOrNull(
          (c) => c.uuid.toLowerCase() == uuid.toLowerCase(),
        ) ??
        characteristics.firstWhereOrNull((c) => matches(c.properties));
  }

  /// Drops the link.
  Future<void> disconnect() async {
    if (_address case final address?) await _ble.disconnect(address);
    _forgetLink();
    notifyListeners();
  }

  /// Writes [bytes] to the peripheral's RX characteristic.
  ///
  /// [withoutResponse] skips the ATT acknowledgement, which is what the game
  /// uses: a paddle position that misses is worth less than one that is late.
  Future<bool> write(Uint8List bytes, {bool withoutResponse = false}) async {
    final address = _address;
    final rx = _rx;
    if (address == null || rx == null) return false;

    try {
      await _ble.writeCharacteristic(
        address: address,
        serviceUuid: rx.serviceUuid,
        characteristicUuid: rx.uuid,
        value: bytes,
        withoutResponse: withoutResponse,
      );
      telemetry.count(PacketDirection.outbound);
      if (!isGameRunning) {
        _record(bytes, PacketDirection.outbound);
        notifyListeners();
      }
      return true;
    } on PlatformException catch (error) {
      _say('Write failed: ${error.message}', isError: true);
      return false;
    }
  }

  /// Reads the peripheral's TX characteristic, which holds whatever it sent
  /// last.
  Future<void> readTx() => _call('Read TX', () async {
    final tx = _tx;
    if (tx == null) throw StateError('nothing to read');
    final value = await _ble.readCharacteristic(
      address: _address!,
      serviceUuid: tx.serviceUuid,
      characteristicUuid: tx.uuid,
    );
    _record(value, PacketDirection.inbound);
    return formatHexBytes(value);
  });

  /// Reads a descriptor on the TX characteristic.
  ///
  /// The one every notifying characteristic carries is the Client
  /// Characteristic Configuration, `00002902-...`, which is the flag
  /// `setCharacteristicNotification` sets. Reading it back is how you check
  /// the subscription actually took.
  Future<void> readTxDescriptor(String descriptorUuid) =>
      _call('Read descriptor', () async {
        final tx = _tx;
        if (tx == null) throw StateError('nothing to read');
        final value = await _ble.readDescriptor(
          address: _address!,
          serviceUuid: tx.serviceUuid,
          characteristicUuid: tx.uuid,
          descriptorUuid: descriptorUuid,
        );
        return value.isEmpty ? 'empty' : formatHexBytes(value);
      });

  /// Writes a descriptor on the TX characteristic.
  Future<void> writeTxDescriptor(
    String descriptorUuid,
    Uint8List value,
  ) => _call('Write descriptor', () async {
    final tx = _tx;
    if (tx == null) throw StateError('nothing to write');
    await _ble.writeDescriptor(
      address: _address!,
      serviceUuid: tx.serviceUuid,
      characteristicUuid: tx.uuid,
      descriptorUuid: descriptorUuid,
      value: value,
    );
    return formatHexBytes(value);
  });

  /// Turns the subscription to TX on or off.
  Future<void> setNotifications({required bool enable}) =>
      _call('Notifications', () async {
        final tx = _tx;
        if (tx == null) throw StateError('nothing to subscribe to');
        await _ble.setCharacteristicNotification(
          address: _address!,
          serviceUuid: tx.serviceUuid,
          characteristicUuid: tx.uuid,
          enable: enable,
        );
        return enable ? 'on' : 'off';
      });

  /// Asks for a larger MTU. Only Android chooses; the others report what the
  /// link already negotiated.
  Future<void> requestMtu(int mtu) => _call('MTU', () async {
    _mtu = await _ble.requestMtu(address: _address!, mtu: mtu);
    return '$_mtu bytes';
  });

  /// Reads the signal strength of the link itself, rather than of an
  /// advertisement.
  Future<void> readRssi() => _call('RSSI', () async {
    _linkRssi = await _ble.readRssi(_address!);
    _reportLinkQuality(_linkRssi);
    return '$_linkRssi dBm';
  });

  /// Asks the platform where the connection stands, rather than trusting the
  /// stream.
  Future<void> readConnectionState() => _call('Connection state', () async {
    _connectionState = await _ble.getConnectionState(_address!);
    return _connectionState.name;
  });

  /// Starts pairing. The outcome arrives on the bond stream, not from here.
  Future<void> createBond() => _call(
    'Pair',
    () async => _ble.createBond(_address!).then((_) => 'asked'),
  );

  /// Removes the pairing.
  Future<void> removeBond() => _call(
    'Unpair',
    () async => _ble.removeBond(_address!).then((_) => 'asked'),
  );

  /// Reads the current bond.
  Future<void> readBondState() => _call('Bond', () async {
    _bondState = await _ble.getBondState(_address!);
    return _bondState!.name;
  });

  /// Asks for a faster or slower connection interval.
  ///
  /// A game wants [ConnectionPriority.high], which on Android is an 11.25 to
  /// 15 ms interval instead of the default 30 to 50.
  Future<void> setPriority(ConnectionPriority priority) => _call(
    'Connection priority',
    () async => _ble
        .requestConnectionPriority(address: _address!, priority: priority)
        .then((_) => priority.name),
  );

  /// Reads which PHY the link settled on.
  Future<void> readPhy() => _call('PHY', () async {
    final phy = await _ble.readPhy(_address!);
    return 'tx ${phy.tx.name}, rx ${phy.rx.name}';
  });

  /// Asks for a PHY. It is a request: read it back to see what was agreed.
  Future<void> setPreferredPhy(GattPhy phy) => _call(
    'Preferred PHY',
    () async => _ble
        .setPreferredPhy(address: _address!, txPhy: phy, rxPhy: phy)
        .then((_) => phy.name),
  );

  /// Opens a reliable write transaction.
  Future<void> beginReliableWrite() => _call(
    'Reliable write',
    () async => _ble.beginReliableWrite(_address!).then((_) => 'open'),
  );

  /// Commits one.
  Future<void> executeReliableWrite() => _call(
    'Reliable write',
    () async => _ble.executeReliableWrite(_address!).then((_) => 'committed'),
  );

  /// Abandons one.
  Future<void> abortReliableWrite() => _call(
    'Reliable write',
    () async => _ble.abortReliableWrite(_address!).then((_) => 'aborted'),
  );

  /// Runs a plugin call and says what it did.
  ///
  /// Every optional call on this page goes through here, so a platform that
  /// does not serve one says so in the same words each time instead of each
  /// caller inventing its own.
  Future<void> _call(String label, Future<String> Function() body) async {
    if (_address == null) return;
    try {
      _say('$label: ${await body()}');
    } on PlatformException catch (error) {
      _say(
        error.code == 'unsupported'
            ? '$label is not supported on this platform'
            : '$label failed: ${error.message}',
        isError: true,
      );
    }
    notifyListeners();
  }

  // Housekeeping -----------------------------------------------------------

  void _forgetLink() {
    _address = null;
    _peerName = null;
    _connectionState = GattConnectionState.disconnected;
    _services = const [];
    _tx = null;
    _rx = null;
    _mtu = null;
    _linkRssi = null;
    _bondState = null;
    _traffic.clear();
    telemetry.clear();
  }

  void _record(Uint8List bytes, PacketDirection direction) {
    _traffic.insert(
      0,
      (bytes: bytes, direction: direction, at: DateTime.now()),
    );
    if (_traffic.length > 50) _traffic.removeLast();
  }

  /// Plots an RSSI on the link meter, mapping -100..-40 dBm onto the strip.
  void _reportLinkQuality(int? rssi) {
    telemetry.report(
      grade: SignalGrade.fromRssi(rssi),
      caption: rssi == null ? 'connected' : '$rssi dBm',
      level: rssi == null ? 0.5 : ((rssi + 100) / 60).clamp(0.0, 1.0),
    );
  }

  void _say(String message, {bool isError = false}) {
    notice.value = (message: message, isError: isError);
  }

  // RadioAccess ------------------------------------------------------------

  @override
  Future<bool> get isSupported => _ble.isSupported;

  @override
  Future<bool> get isPoweredOn => _ble.isBluetoothOn;

  @override
  Future<AccessState> check() async => (await _ble.hasPermission()).access;

  @override
  Future<AccessState> request() async =>
      (await _ble.requestPermission()).access;

  @override
  Future<bool> powerOn() => _ble.enableBluetooth();

  @override
  Future<void> openAppSettings() => _ble.openAppSettings();

  @override
  Future<void> openRadioSettings() => _ble.openBluetoothSettings();
}

/// Maps the plugin's answer onto the one the shell speaks.
extension on CentralBluetoothState {
  AccessState get access => switch (this) {
    CentralBluetoothState.ready => AccessState.ready,
    CentralBluetoothState.granted => AccessState.granted,
    CentralBluetoothState.denied => AccessState.denied,
    CentralBluetoothState.permanentlyDenied => AccessState.permanentlyDenied,
    CentralBluetoothState.turnedOff => AccessState.turnedOff,
    CentralBluetoothState.unsupported => AccessState.unsupported,
    CentralBluetoothState.restricted => AccessState.restricted,
    CentralBluetoothState.limited => AccessState.limited,
    CentralBluetoothState.unknown => AccessState.unknown,
  };
}

/// The missing `firstWhereOrNull`.
///
/// package:collection has this one; it is inlined so the
/// example stays free of dependencies beyond the plugin itself.
extension FirstWhereOrNull<T> on Iterable<T> {
  /// Returns the first element [test] accepts, or null.
  T? firstWhereOrNull(bool Function(T element) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
