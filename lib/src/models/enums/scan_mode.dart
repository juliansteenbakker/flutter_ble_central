/*
 * Copyright (c) 2022. Julian Steenbakker.
 * All rights reserved. Use of this source code is governed by a
 * BSD-style license that can be found in the LICENSE file.
 */

import 'package:json_annotation/json_annotation.dart';

/// BLE scan mode enum
enum ScanMode {
  /// A special Bluetooth LE scan mode.
  /// Applications using this scan mode will passively listen for
  /// other scan results without starting BLE scans themselves.
  @JsonValue(-1)
  scanModeOpportunistic,

  /// Perform Bluetooth LE advertising in low power mode.
  /// This is the default and preferred advertising mode
  /// as it consumes the least power.
  @JsonValue(0)
  scanModeLowPower,

  /// Perform Bluetooth LE advertising in balanced power mode.
  /// This is balanced between advertising frequency
  /// and power consumption.
  @JsonValue(1)
  scanModeBalanced,

  /// Perform Bluetooth LE advertising in low latency, high power mode.
  /// This has the highest power consumption and should not be used
  /// for continuous background advertising.
  @JsonValue(2)
  scanModeLowLatency,
}
