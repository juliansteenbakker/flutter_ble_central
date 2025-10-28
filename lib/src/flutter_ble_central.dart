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
import 'package:flutter_ble_central/src/models/enums/bluetooth_central_state.dart';
import 'package:flutter_ble_central/src/models/enums/central_state.dart';
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
  final MethodChannel _methodChannel =
      const MethodChannel('dev.steenbakker.flutter_ble_central/method');

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

  Stream<ScanResult>? _scanResult;
  StreamTransformer<dynamic, ScanResult>? _scanResultTransformer;

  Stream<int>? _scanError;
  Stream<CentralState>? _centralState;

  /// Start scanning. Takes [ScanSettings] as an input.
  Future<BluetoothCentralState> start({
    ScanSettings? scanSettings,
  }) async {
    final settings = (scanSettings ?? ScanSettings()).toJson();
    settings['enableTimingStats'] = enableTimingStats;

    if (Platform.isWindows) {
      try {
        await _methodChannel.invokeMethod('start', settings);
      } on PlatformException catch (e) {
        debugPrint('$tag platform exception: $e');
        return BluetoothCentralState.turnedOff;
      }
      return BluetoothCentralState.ready;
    }
    final response = await _methodChannel.invokeMethod<int>('start', settings);
    return response == null
        ? BluetoothCentralState.unknown
        : BluetoothCentralState.values[response];
  }

  /// Stop advertising
  Future<BluetoothCentralState> stop() async {
    if (Platform.isWindows) {
      await _methodChannel.invokeMethod<bool>('stop');
      return BluetoothCentralState.ready;
    }
    final response = await _methodChannel.invokeMethod<int>('stop');
    return response == null
        ? BluetoothCentralState.unknown
        : BluetoothCentralState.values[response];
  }

  /// Returns `true` if advertising or false if not advertising
  Future<bool> get isAdvertising async {
    return await _methodChannel.invokeMethod<bool>('isAdvertising') ?? false;
  }

  /// Returns `true` if advertising over BLE is supported
  Future<bool> get isSupported async =>
      await _methodChannel.invokeMethod<bool>('isSupported') ?? false;

  /// Enable Bluetooth
  Future<bool> enableBluetooth({bool askUser = true}) async {
    return await _methodChannel.invokeMethod<bool>(
          'enableBluetooth',
          askUser,
        ) ??
        false;
  }

  /// Request Bluetooth permissions
  Future<BluetoothCentralState> requestPermission() async {
    final response =
        await _methodChannel.invokeMethod<int>('requestPermission');
    return response == null
        ? BluetoothCentralState.unknown
        : BluetoothCentralState.values[response];
  }

  /// Check if Bluetooth permissions are granted
  Future<BluetoothCentralState> hasPermission() async {
    final response = await _methodChannel.invokeMethod<int>('hasPermission');
    return response == null
        ? BluetoothCentralState.unknown
        : BluetoothCentralState.values[response];
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
    _scanResultTransformer ??=
        StreamTransformer.fromHandlers(handleData: handleData);
    _scanResult ??= _scanResultEventChannel
        .receiveBroadcastStream()
        .transform(_scanResultTransformer!);

    return _scanResult!;
  }

  /// Returns Stream of MTU updates.
  Stream<int>? get onScanError {
    if (!Platform.isAndroid) return null;
    _scanResultTransformer ??=
        StreamTransformer.fromHandlers(handleData: handleData);
    return _scanError ??= _scanErrorEventChannel
        .receiveBroadcastStream()
        .map((dynamic event) => event as int);
  }

  /// Returns Stream of state.
  ///
  /// After listening to this Stream,
  /// you'll be notified about changes in peripheral state.
  Stream<CentralState> get onPeripheralStateChanged {
    _centralState ??= _stateChangedEventChannel
        .receiveBroadcastStream()
        .map((dynamic event) => CentralState.values[event as int]);
    return _centralState!;
  }

  /// Returns Stream of MTU updates.
  Stream<dynamic> get onRawScanResult {
    return _scanResultEventChannel.receiveBroadcastStream();
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

      raw['device'] = {
        'address': raw['address'] ?? '',
      };

      result = ScanResult.fromPlatform(raw);
    } else {
      result = ScanResult.fromPlatform(data as Map<Object?, Object?>);
    }

    sink.add(result);
  }
}
