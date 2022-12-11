/*
 * Copyright (c) 2020. Julian Steenbakker.
 * All rights reserved. Use of this source code is governed by a
 * BSD-style license that can be found in the LICENSE file.
 */

enum CentralState {
  /// Status is not (yet) determined.
  unknown,

  /// BLE is not supported on this device.
  unsupported,

  /// BLE usage is not authorized for this app.
  unauthorized,

  /// BLE is turned off.
  poweredOff,

  /// BLE is fully operating for this app.
  idle,

  /// BLE is advertising data.
  advertising,

  /// BLE is connected to a device.
  connected,
}

extension PeripheralStateExtension on CentralState {
  int get code {
    switch (this) {
      case CentralState.unknown:
        return 10;
      case CentralState.unsupported:
        return 11;
      case CentralState.unauthorized:
        return 12;
      case CentralState.poweredOff:
        return 13;
      case CentralState.idle:
        return 14;
      case CentralState.advertising:
        return 15;
      case CentralState.connected:
        return 16;
    }
  }
}
