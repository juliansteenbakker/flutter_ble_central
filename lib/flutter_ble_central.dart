
import 'dart:async';

import 'package:flutter/services.dart';

class FlutterBleCentral {
  static const MethodChannel _channel = MethodChannel('flutter_ble_central');

  static Future<String?> get platformVersion async {
    final String? version = await _channel.invokeMethod('getPlatformVersion');
    return version;
  }
}
