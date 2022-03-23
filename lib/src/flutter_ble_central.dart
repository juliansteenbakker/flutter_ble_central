/*
 * Copyright (c) 2022. Julian Steenbakker.
 * All rights reserved. Use of this source code is governed by a
 * BSD-style license that can be found in the LICENSE file.
 */

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_ble_central/src/models/scan_result.dart';

class FlutterBleCentral {
  /// Singleton instance
  static final FlutterBleCentral _instance =
  FlutterBleCentral._internal();

  /// Singleton factory
  factory FlutterBleCentral() {
    return _instance;
  }

  /// Singleton constructor
  FlutterBleCentral._internal();

  /// Method Channel used to communicate state with
  final MethodChannel _methodChannel =
  const MethodChannel('dev.steenbakker.flutter_ble_central/method');

  /// Event Channel for MTU state
  final EventChannel _scanResultEventChannel = const EventChannel(
    'dev.steenbakker.flutter_ble_central/scan_result', );

  Stream<ScanResult>? _scanResult;
  StreamTransformer<dynamic, ScanResult>? _scanResultTransformer;


  //TODO Event Channel used to received data
  // final EventChannel _dataReceivedEventChannel = const EventChannel(
  //     'dev.steenbakker.flutter_ble_peripheral/ble_data_received');

  /// Start advertising. Takes [AdvertiseData] as an input.
  Future<void> start() async {
    return _methodChannel.invokeMethod('start');
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
      'enableBluetooth', askUser,) ??
        false;
  }

  /// Returns Stream of MTU updates.
  Stream<ScanResult> get onScanResult {

    _scanResultTransformer ??= StreamTransformer.fromHandlers(handleData: handleData);
    _scanResult ??= _scanResultEventChannel
        .receiveBroadcastStream().transform(_scanResultTransformer!);

    return _scanResult!;
  }



  void handleData(data, EventSink sink) {
    final ScanResult result = ScanResult.fromJson(jsonDecode(data));
    sink.add(result);
  }


}
