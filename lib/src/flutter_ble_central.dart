/*
 * Copyright (c) 2022. Julian Steenbakker.
 * All rights reserved. Use of this source code is governed by a
 * BSD-style license that can be found in the LICENSE file.
 */

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_ble_central/src/models/enums/central_state.dart';
import 'package:flutter_ble_central/src/models/scan_result.dart';
import 'package:flutter_ble_central/src/models/scan_settings.dart';

class FlutterBleCentral {
  /// Singleton instance
  static final FlutterBleCentral _instance = FlutterBleCentral._internal();

  /// Singleton factory
  factory FlutterBleCentral() {
    return _instance;
  }

  /// Singleton constructor
  FlutterBleCentral._internal();

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

  /// Start advertising. Takes [AdvertiseData] as an input.
  Future<void> start({
    ScanSettings? scanSettings,
  }) async {
    return _methodChannel.invokeMethod('start', scanSettings?.toJson());
  }

  /// Stop advertising
  Future<void> stop() async {
    return _methodChannel.invokeMethod('stop');
  }

  /// Returns `true` if advertising or false if not advertising
  Future<bool> get isAdvertising async {
    return await _methodChannel.invokeMethod<bool>('isAdvertising') ?? false;
  }

  /// Returns `true` if advertising over BLE is supported
  Future<bool> get isSupported async =>
      await _methodChannel.invokeMethod<bool>('isSupported') ?? false;

  /// Stop advertising
  Future<bool> enableBluetooth({bool askUser = true}) async {
    return await _methodChannel.invokeMethod<bool>(
          'enableBluetooth',
          askUser,
        ) ??
        false;
  }

  Future<bool> requestPermission() async {
    return await _methodChannel.invokeMethod<bool>('requestPermissions') ??
        false;
  }

  Future<bool> hasPermission() async {
    return await _methodChannel.invokeMethod<bool>('hasPermission') ?? false;
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
  /// After listening to this Stream, you'll be notified about changes in peripheral state.
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
  void handleData(dynamic data, EventSink sink) {
    ScanResult? result;
    if (Platform.isIOS || Platform.isMacOS) {
      data as Map<dynamic, dynamic>;

      final Uint8List manufacturerIdAndData =
          data["manufacturerSpecificData"] as Uint8List;
      Map<String, dynamic> manufacturerSpecificData = {};

      // Check that both manufacturerID AND data is present
      if (manufacturerIdAndData.length >= 3) {
        manufacturerSpecificData = {
          "${manufacturerIdAndData[0] | manufacturerIdAndData[1] << 8}":
              manufacturerIdAndData.skip(2).toList()
        };
      }

      final Map<String, dynamic> scanRecord = {
        'deviceName': data['deviceName'],
        'manufacturerSpecificData': manufacturerSpecificData,
        'serviceData': data['serviceData'],
        'serviceUuids': data['serviceUuids'],
      };

      data['scanRecord'] = scanRecord;
      data['device'] = {'address': data['address']};

      result = ScanResult.fromJson(Map<String, dynamic>.from(data));
    } else {
      result = ScanResult.fromJson(
        jsonDecode(data as String) as Map<String, dynamic>,
      );
    }
    sink.add(result);
  }
}
