/*
 * Copyright (c) 2026. Julian Steenbakker.
 * All rights reserved. Use of this source code is governed by a
 * BSD-style license that can be found in the LICENSE file.
 */

import 'package:flutter/material.dart';
import 'package:flutter_ble_central/flutter_ble_central.dart';
import 'package:flutter_ble_central_example/central_controller.dart';
import 'package:flutter_ble_central_example/pages/data_page.dart';
import 'package:flutter_ble_central_example/pages/link_page.dart';
import 'package:flutter_ble_central_example/pages/pong_page.dart';
import 'package:flutter_ble_central_example/pages/setup_page.dart';
import 'package:flutter_ble_central_example/shell/shell.dart';

/// The central example: one controller, four pages over it.
class CentralHome extends StatefulWidget {
  /// Creates the app.
  const CentralHome({super.key});

  @override
  State<CentralHome> createState() => _CentralHomeState();
}

class _CentralHomeState extends State<CentralHome> {
  final _controller = CentralController();

  @override
  void initState() {
    super.initState();
    _controller.notice.addListener(_showNotice);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ensureRadioReady(context, _controller);
    });
  }

  @override
  void dispose() {
    _controller
      ..notice.removeListener(_showNotice)
      ..dispose();
    super.dispose();
  }

  void _showNotice() {
    if (_controller.notice.value case final notice? when mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(notice.message),
            backgroundColor: notice.isError ? SignalGrade.weak.color : null,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => InstrumentScaffold(
        telemetry: _controller.telemetry,
        adapterState: _controller.adapterState.name,
        adapterGrade: _controller.adapterState.grade,
        linked: _controller.isConnected,
        destinations: [
          Destination(
            label: 'Link',
            icon: Icons.settings_input_antenna,
            builder: (_) => LinkPage(controller: _controller),
          ),
          Destination(
            label: 'Data',
            icon: Icons.swap_vert,
            builder: (_) => DataPage(controller: _controller),
          ),
          Destination(
            label: 'Pong',
            icon: Icons.sports_tennis,
            builder: (_) => PongPage(controller: _controller),
          ),
          Destination(
            label: 'Setup',
            icon: Icons.tune,
            builder: (_) => SetupPage(controller: _controller),
          ),
        ],
      ),
    );
  }
}

/// How healthy each adapter state is, on the shell's one ramp.
extension CentralStateGrade on CentralState {
  /// The grade the status rail lights this state in.
  SignalGrade get grade => switch (this) {
    CentralState.idle || CentralState.connected => SignalGrade.strong,
    CentralState.advertising => SignalGrade.fair,
    CentralState.poweredOff || CentralState.unknown => SignalGrade.weak,
    CentralState.unauthorized || CentralState.unsupported => SignalGrade.none,
  };
}
