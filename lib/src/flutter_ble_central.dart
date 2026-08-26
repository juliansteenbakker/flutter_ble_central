/*
 * Copyright (c) 2022. Julian Steenbakker.
 * All rights reserved. Use of this source code is governed by a
 * BSD-style license that can be found in the LICENSE file.
 */

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ble_central/src/models/enums/bond_state.dart';
import 'package:flutter_ble_central/src/models/enums/central_bluetooth_state.dart';
import 'package:flutter_ble_central/src/models/enums/central_state.dart';
import 'package:flutter_ble_central/src/models/enums/connection_priority.dart';
import 'package:flutter_ble_central/src/models/enums/gatt_connection_state.dart';
import 'package:flutter_ble_central/src/models/enums/gatt_phy.dart';
import 'package:flutter_ble_central/src/models/gatt_events.dart';
import 'package:flutter_ble_central/src/models/gatt_service.dart';
import 'package:flutter_ble_central/src/models/scan_result.dart';
import 'package:flutter_ble_central/src/models/scan_settings.dart';

/// Main class for Flutter BLE Central plugin
class FlutterBleCentral {
  /// Singleton factory
  factory FlutterBleCentral() {
    return _instance;
  }

  /// Singleton constructor
  FlutterBleCentral._internal();

  /// Singleton instance
  static final FlutterBleCentral _instance = FlutterBleCentral._internal();

  /// Tag for logging
  static const tag = 'flutter_ble_central:';

  /// Enables or disables timing statistics logging for scan result processing.
  ///
  /// When enabled, the native handlers will log timing information for each
  /// scan result publish operation, which is useful for performance monitoring.
  ///
  /// Default is `false`.
  bool enableTimingStats = false;

  /// Method Channel used to communicate state with
  final MethodChannel _methodChannel = const MethodChannel(
    'dev.steenbakker.flutter_ble_central/method',
  );

  /// Event Channel for Scan Result
  final EventChannel _scanResultEventChannel = const EventChannel(
    'dev.steenbakker.flutter_ble_central/scan_result',
  );

  /// Event Channel for Scan Error
  final EventChannel _scanErrorEventChannel = const EventChannel(
    'dev.steenbakker.flutter_ble_central/scan_error',
  );

  /// Event Channel used to changed state
  final EventChannel _stateChangedEventChannel = const EventChannel(
    'dev.steenbakker.flutter_ble_central/ble_state_changed',
  );

  /// Event Channel for Connection State
  final EventChannel _connectionStateEventChannel = const EventChannel(
    'dev.steenbakker.flutter_ble_central/connection_state',
  );

  /// Event Channel for Characteristic Notifications
  final EventChannel _characteristicValueEventChannel = const EventChannel(
    'dev.steenbakker.flutter_ble_central/characteristic_value',
  );

  /// Event Channel used to receive pairing state changes
  final EventChannel _bondStateEventChannel = const EventChannel(
    'dev.steenbakker.flutter_ble_central/bond_state',
  );

  Stream<ScanResult>? _scanResult;
  StreamTransformer<dynamic, ScanResult>? _scanResultTransformer;

  Stream<int>? _scanError;
  Stream<CentralState>? _centralState;
  Stream<ConnectionStateChange>? _connectionState;
  Stream<CharacteristicValue>? _characteristicValue;
  Stream<BondStateChange>? _bondState;

  /// Start scanning. Takes [ScanSettings] as an input.
  Future<CentralBluetoothState> start({ScanSettings? scanSettings}) async {
    final settings = (scanSettings ?? ScanSettings()).toJson();
    settings['enableTimingStats'] = enableTimingStats;

    if (Platform.isWindows) {
      try {
        await _methodChannel.invokeMethod('start', settings);
      } on PlatformException catch (e) {
        if (e.code == 'unsupported') return CentralBluetoothState.unsupported;
        debugPrint('$tag platform exception: $e');
        return CentralBluetoothState.turnedOff;
      }
      return CentralBluetoothState.ready;
    }
    final response = await _methodChannel.invokeMethod<int>('start', settings);
    return response == null
        ? CentralBluetoothState.unknown
        : CentralBluetoothState.values[response];
  }

  /// Stop advertising
  Future<CentralBluetoothState> stop() async {
    if (Platform.isWindows) {
      await _methodChannel.invokeMethod<bool>('stop');
      return CentralBluetoothState.ready;
    }
    final response = await _methodChannel.invokeMethod<int>('stop');
    return response == null
        ? CentralBluetoothState.unknown
        : CentralBluetoothState.values[response];
  }

  /// Returns `true` if advertising over BLE is supported
  Future<bool> get isSupported async =>
      await _methodChannel.invokeMethod<bool>('isSupported') ?? false;

  /// Returns `true` if Bluetooth is powered on
  Future<bool> get isBluetoothOn async =>
      await _methodChannel.invokeMethod<bool>('isBluetoothOn') ?? false;

  /// Enable Bluetooth
  Future<bool> enableBluetooth({bool askUser = true}) async {
    return await _methodChannel.invokeMethod<bool>(
          'enableBluetooth',
          askUser,
        ) ??
        false;
  }

  /// Request Bluetooth permissions
  Future<CentralBluetoothState> requestPermission() async {
    final response = await _methodChannel.invokeMethod<int>(
      'requestPermission',
    );
    return response == null
        ? CentralBluetoothState.unknown
        : CentralBluetoothState.values[response];
  }

  /// Check if Bluetooth permissions are granted
  Future<CentralBluetoothState> hasPermission() async {
    final response = await _methodChannel.invokeMethod<int>('hasPermission');
    return response == null
        ? CentralBluetoothState.unknown
        : CentralBluetoothState.values[response];
  }

  /// Open Bluetooth settings
  Future<void> openBluetoothSettings() async {
    await _methodChannel.invokeMethod('openBluetoothSettings');
  }

  /// Open app settings
  Future<void> openAppSettings() async {
    await _methodChannel.invokeMethod('openAppSettings');
  }

  /// Returns Stream of MTU updates.
  Stream<ScanResult> get onScanResult {
    _scanResultTransformer ??= StreamTransformer.fromHandlers(
      handleData: handleData,
    );
    _scanResult ??= _scanResultEventChannel.receiveBroadcastStream().transform(
          _scanResultTransformer!,
        );

    return _scanResult!;
  }

  /// Returns Stream of MTU updates.
  Stream<int>? get onScanError {
    if (!Platform.isAndroid) return null;
    _scanResultTransformer ??= StreamTransformer.fromHandlers(
      handleData: handleData,
    );
    return _scanError ??= _scanErrorEventChannel.receiveBroadcastStream().map(
          (dynamic event) => event as int,
        );
  }

  /// Returns Stream of state.
  ///
  /// After listening to this Stream,
  /// you'll be notified about changes in peripheral state.
  Stream<CentralState> get onCentralStateChanged {
    _centralState ??= _stateChangedEventChannel.receiveBroadcastStream().map(
          (dynamic event) => CentralState.values[event as int],
        );
    return _centralState!;
  }

  /// Returns Stream of MTU updates.
  Stream<dynamic> get onRawScanResult {
    return _scanResultEventChannel.receiveBroadcastStream();
  }

  /// Returns Stream of connection state changes.
  ///
  /// The stream emits maps with 'address' and 'state' keys.
  Stream<ConnectionStateChange> get onConnectionStateChanged {
    _connectionState ??=
        _connectionStateEventChannel.receiveBroadcastStream().map(
              (dynamic event) => ConnectionStateChange.fromPlatform(
                event as Map<Object?, Object?>,
              ),
            );
    return _connectionState!;
  }

  /// Returns a Stream of pairing state changes.
  ///
  /// Emits whenever this device starts pairing with a peripheral, finishes, or
  /// loses the pairing. Android only.
  Stream<BondStateChange> get onBondStateChanged {
    _bondState ??= _bondStateEventChannel.receiveBroadcastStream().map(
          (dynamic event) =>
              BondStateChange.fromPlatform(event as Map<Object?, Object?>),
        );
    return _bondState!;
  }

  /// Returns Stream of characteristic value notifications.
  ///
  /// The stream emits maps with characteristic data and values.
  Stream<CharacteristicValue> get onCharacteristicValueChanged {
    _characteristicValue ??=
        _characteristicValueEventChannel.receiveBroadcastStream().map(
              (dynamic event) => CharacteristicValue.fromPlatform(
                event as Map<Object?, Object?>,
              ),
            );
    return _characteristicValue!;
  }

  // Connection Management

  /// Connect to a Bluetooth device.
  ///
  /// [address] The device address to connect to
  /// [autoConnect] Whether to automatically connect when device is available
  /// [timeout] Connection timeout in seconds (default: 15)
  Future<void> connect({
    required String address,
    bool autoConnect = false,
    int timeout = 15,
  }) async {
    await _methodChannel.invokeMethod('connect', {
      'address': address,
      'autoConnect': autoConnect,
      'timeout': timeout,
    });
  }

  /// Disconnect from a Bluetooth device.
  ///
  /// [address] The device address to disconnect from
  Future<void> disconnect(String address) async {
    await _methodChannel.invokeMethod('disconnect', {'address': address});
  }

  /// Get the current connection state of a device.
  ///
  /// [address] The device address
  /// Returns the [GattConnectionState] of the device
  Future<GattConnectionState> getConnectionState(String address) async {
    final response = await _methodChannel.invokeMethod<int>(
      'getConnectionState',
      {'address': address},
    );
    return response == null
        ? GattConnectionState.disconnected
        : GattConnectionState.values[response];
  }

  // Service Discovery

  /// Discover GATT services on a connected device.
  ///
  /// [address] The device address
  /// Returns a list of [GattService] discovered
  Future<List<GattService>> discoverServices(String address) async {
    final response = await _methodChannel.invokeMethod<List<Object?>>(
      'discoverServices',
      {'address': address},
    );
    if (response == null) return [];
    return response
        .map(
          (e) => GattService.fromJson(
            Map<String, dynamic>.from(e! as Map),
          ),
        )
        .toList();
  }

  // Characteristic Operations

  /// Read the value of a characteristic.
  ///
  /// [address] The device address
  /// [serviceUuid] The service UUID
  /// [characteristicUuid] The characteristic UUID
  /// Returns the characteristic value as [Uint8List]
  Future<Uint8List> readCharacteristic({
    required String address,
    required String serviceUuid,
    required String characteristicUuid,
  }) async {
    final response = await _methodChannel.invokeMethod<List<Object?>>(
      'readCharacteristic',
      {
        'address': address,
        'serviceUuid': serviceUuid,
        'characteristicUuid': characteristicUuid,
      },
    );
    if (response == null) return Uint8List(0);
    return Uint8List.fromList(response.cast<int>());
  }

  /// Write a value to a characteristic.
  ///
  /// [address] The device address
  /// [serviceUuid] The service UUID
  /// [characteristicUuid] The characteristic UUID
  /// [value] The value to write
  /// [withoutResponse] Whether to write without response
  Future<void> writeCharacteristic({
    required String address,
    required String serviceUuid,
    required String characteristicUuid,
    required Uint8List value,
    bool withoutResponse = false,
  }) async {
    await _methodChannel.invokeMethod('writeCharacteristic', {
      'address': address,
      'serviceUuid': serviceUuid,
      'characteristicUuid': characteristicUuid,
      'value': value,
      'withoutResponse': withoutResponse,
    });
  }

  /// Enable or disable notifications on a characteristic.
  ///
  /// [address] The device address
  /// [serviceUuid] The service UUID
  /// [characteristicUuid] The characteristic UUID
  /// [enable] Whether to enable or disable notifications
  Future<void> setCharacteristicNotification({
    required String address,
    required String serviceUuid,
    required String characteristicUuid,
    required bool enable,
  }) async {
    await _methodChannel.invokeMethod('setCharacteristicNotification', {
      'address': address,
      'serviceUuid': serviceUuid,
      'characteristicUuid': characteristicUuid,
      'enable': enable,
    });
  }

  // Descriptor Operations

  /// Read the value of a descriptor.
  ///
  /// [address] The device address
  /// [serviceUuid] The service UUID
  /// [characteristicUuid] The characteristic UUID
  /// [descriptorUuid] The descriptor UUID
  /// Returns the descriptor value as [Uint8List]
  Future<Uint8List> readDescriptor({
    required String address,
    required String serviceUuid,
    required String characteristicUuid,
    required String descriptorUuid,
  }) async {
    final response = await _methodChannel.invokeMethod<List<Object?>>(
      'readDescriptor',
      {
        'address': address,
        'serviceUuid': serviceUuid,
        'characteristicUuid': characteristicUuid,
        'descriptorUuid': descriptorUuid,
      },
    );
    if (response == null) return Uint8List(0);
    return Uint8List.fromList(response.cast<int>());
  }

  /// Write a value to a descriptor.
  ///
  /// [address] The device address
  /// [serviceUuid] The service UUID
  /// [characteristicUuid] The characteristic UUID
  /// [descriptorUuid] The descriptor UUID
  /// [value] The value to write
  Future<void> writeDescriptor({
    required String address,
    required String serviceUuid,
    required String characteristicUuid,
    required String descriptorUuid,
    required Uint8List value,
  }) async {
    await _methodChannel.invokeMethod('writeDescriptor', {
      'address': address,
      'serviceUuid': serviceUuid,
      'characteristicUuid': characteristicUuid,
      'descriptorUuid': descriptorUuid,
      'value': value,
    });
  }

  /// Request a specific MTU size.
  ///
  /// [address] The device address
  /// [mtu] The requested MTU size
  /// Returns the negotiated MTU size
  Future<int> requestMtu({
    required String address,
    required int mtu,
  }) async {
    final response = await _methodChannel.invokeMethod<int>(
      'requestMtu',
      {
        'address': address,
        'mtu': mtu,
      },
    );
    return response ?? 23; // Default MTU
  }

  /// Read the RSSI of a connected device.
  ///
  /// [address] The device address
  /// Returns the RSSI value
  Future<int> readRssi(String address) async {
    final response = await _methodChannel.invokeMethod<int>(
      'readRssi',
      {'address': address},
    );
    return response ?? 0;
  }

  // Pairing

  /// Starts pairing with a peripheral.
  ///
  /// Returns as soon as the request is in; the outcome arrives on
  /// [onBondStateChanged], since pairing usually needs the user to confirm it.
  /// Android only.
  Future<void> createBond(String address) async {
    await _methodChannel.invokeMethod('createBond', {'address': address});
  }

  /// Removes the pairing with a peripheral.
  ///
  /// Android only, and uses a hidden platform API, so it may fail on some
  /// devices.
  Future<void> removeBond(String address) async {
    await _methodChannel.invokeMethod('removeBond', {'address': address});
  }

  /// Whether this device is paired with a peripheral. Android only.
  Future<BondState> getBondState(String address) async {
    final response = await _methodChannel.invokeMethod<int>(
      'getBondState',
      {'address': address},
    );
    return BondState.fromValue(response ?? BondState.none.value);
  }

  // Connection tuning

  /// Asks for a connection interval suited to [priority].
  ///
  /// A shorter interval means lower latency and higher throughput at the cost
  /// of power. The peripheral has the final say. Android only.
  Future<void> requestConnectionPriority({
    required String address,
    required ConnectionPriority priority,
  }) async {
    await _methodChannel.invokeMethod('requestConnectionPriority', {
      'address': address,
      'priority': priority.value,
    });
  }

  /// The physical layer the connection is running on.
  ///
  /// Android 8.0 and above only.
  Future<({GattPhy tx, GattPhy rx})> readPhy(String address) async {
    final response = await _methodChannel.invokeMethod<Map<Object?, Object?>>(
      'readPhy',
      {'address': address},
    );
    return (
      tx: GattPhy.fromValue(response?['txPhy'] as int? ?? GattPhy.le1M.value),
      rx: GattPhy.fromValue(response?['rxPhy'] as int? ?? GattPhy.le1M.value),
    );
  }

  /// Asks to move the connection onto [txPhy] and [rxPhy].
  ///
  /// [phyOption] only applies to [GattPhy.leCoded]. Returns as soon as the
  /// request is in; read it back with [readPhy] to see what was agreed, since
  /// the peripheral and the controller both have a say. Android 8.0 and above
  /// only.
  Future<void> setPreferredPhy({
    required String address,
    required GattPhy txPhy,
    required GattPhy rxPhy,
    PhyOption phyOption = PhyOption.noPreferred,
  }) async {
    await _methodChannel.invokeMethod('setPreferredPhy', {
      'address': address,
      'txPhy': txPhy.value,
      'rxPhy': rxPhy.value,
      'phyOptions': phyOption.value,
    });
  }

  // Reliable write

  /// Opens a reliable write transaction.
  ///
  /// Writes made after this are queued on the peripheral and echoed back for
  /// verification rather than applied, until [executeReliableWrite] commits
  /// them or [abortReliableWrite] drops them. Android only.
  Future<void> beginReliableWrite(String address) async {
    await _methodChannel.invokeMethod(
      'beginReliableWrite',
      {'address': address},
    );
  }

  /// Commits the writes queued since [beginReliableWrite]. Android only.
  Future<void> executeReliableWrite(String address) async {
    await _methodChannel.invokeMethod(
      'executeReliableWrite',
      {'address': address},
    );
  }

  /// Drops the writes queued since [beginReliableWrite]. Android only.
  Future<void> abortReliableWrite(String address) async {
    await _methodChannel.invokeMethod(
      'abortReliableWrite',
      {'address': address},
    );
  }

  /// Parses the received data.
  void handleData(dynamic data, EventSink<ScanResult> sink) {
    ScanResult? result;

    if (Platform.isIOS || Platform.isMacOS || Platform.isWindows) {
      final raw = Map<String, dynamic>.from(data as Map);

      // Safely extract manufacturer data
      // Safe conversion of manufacturerSpecificData to Uint8List
      Uint8List? manufacturerIdAndData;
      final dynamic mData = raw['manufacturerSpecificData'];
      if (mData is Uint8List) {
        manufacturerIdAndData = mData;
      } else if (mData is List) {
        manufacturerIdAndData = Uint8List.fromList(mData.cast<int>());
      }

      if (Platform.isWindows) {
        final manufacturerId = raw['manufacturerId'] as int?;
        if (manufacturerId != null && manufacturerIdAndData != null) {
          final b = BytesBuilder();
          final l1 = Uint8List(2)..buffer.asInt16List()[0] = manufacturerId;
          b
            ..add(l1)
            ..add(manufacturerIdAndData);
          manufacturerIdAndData = b.toBytes();
        }
      }

      var manufacturerSpecificData = <String, dynamic>{};
      if (manufacturerIdAndData != null && manufacturerIdAndData.length >= 3) {
        final id = manufacturerIdAndData[0] | (manufacturerIdAndData[1] << 8);
        final value = manufacturerIdAndData.sublist(2);
        manufacturerSpecificData = {id.toString(): value};
      }

      raw['scanRecord'] = {
        'deviceName': raw['deviceName'],
        'manufacturerSpecificData':
            manufacturerSpecificData.isEmpty ? null : manufacturerSpecificData,
        'serviceData': raw['serviceData'] ?? <String, dynamic>{},
        'serviceUuids': raw['serviceUuids'] ?? <String>[],
      };

      raw['device'] = {'address': raw['address'] ?? ''};

      result = ScanResult.fromPlatform(raw);
    } else {
      result = ScanResult.fromPlatform(data as Map<Object?, Object?>);
    }

    sink.add(result);
  }
}
