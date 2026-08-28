/*
 * Copyright (c) 2022. Julian Steenbakker.
 * All rights reserved. Use of this source code is governed by a
 * BSD-style license that can be found in the LICENSE file.
 */

import 'package:flutter/material.dart';
import 'package:flutter_ble_central_example/central_app.dart';
import 'package:flutter_ble_central_example/shell/shell.dart';

void main() => runApp(
  const InstrumentApp(role: DeviceRole.central, home: CentralHome()),
);
