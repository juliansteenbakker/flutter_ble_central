/*
 * Copyright (c) 2026. Julian Steenbakker.
 * All rights reserved. Use of this source code is governed by a
 * BSD-style license that can be found in the LICENSE file.
 */

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_ble_central_example/central_controller.dart';
import 'package:flutter_ble_central_example/central_pong_transport.dart';
import 'package:flutter_ble_central_example/pong/pong.dart';
import 'package:flutter_ble_central_example/shell/shell.dart';

/// How a game is being played.
enum PongMode {
  /// Two devices, over the real link. This end is the guest.
  live('Two devices', 'You play the peripheral over the GATT link'),

  /// One device, over a loopback that still encodes and decodes every
  /// message.
  auto('One device', 'Both paddles play themselves over a simulated link');

  const PongMode(this.label, this.blurb);

  /// The word on the selector.
  final String label;

  /// What choosing it does.
  final String blurb;
}

/// The game. The central is always the guest: the peripheral owns the ball.
class PongPage extends StatefulWidget {
  /// Creates the page over [controller].
  const PongPage({required this.controller, super.key});

  /// The one controller the app runs on.
  final CentralController controller;

  @override
  State<PongPage> createState() => _PongPageState();
}

class _PongPageState extends State<PongPage> with TickerProviderStateMixin {
  PongMode _mode = PongMode.auto;
  LoopbackLink? _loopback;
  CentralPongTransport? _wire;
  PongHost? _localHost;
  PongGuest? _guest;

  CentralController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _mode = _controller.isConnected ? PongMode.live : PongMode.auto;
    _build();
  }

  @override
  void dispose() {
    _tearDown();
    super.dispose();
  }

  /// Builds the players for the current mode.
  ///
  /// Auto mode runs a host and a guest in this process, wired to each other
  /// through the loopback, and draws the guest: what is on screen is what came
  /// off the wire, not what the simulation happened to be thinking.
  void _build() {
    switch (_mode) {
      case PongMode.auto:
        // The default delay is a fair impression of a real connection
        // interval, so a game watched on one device feels like a game played
        // on two.
        final loopback = LoopbackLink();
        _loopback = loopback;
        _localHost = PongHost(
          transport: loopback.host,
          vsync: this,
          autoSelf: PongAutoPlayer(side: PongSide.host, difficulty: 0.7),
        );
        _guest = PongGuest(
          // Counted so the meter reads the same in both modes; over a real
          // link the controller does this on the packets' way through.
          transport: CountedTransport(loopback.guest, onPacket: _count),
          vsync: this,
          auto: PongAutoPlayer(side: PongSide.guest, difficulty: 0.66),
        );
      case PongMode.live:
        final wire = CentralPongTransport(_controller);
        _wire = wire;
        _guest = PongGuest(transport: wire, vsync: this);
    }
    _guest!.addListener(_onFrame);
    _localHost?.resume();
    _guest!.resume();
  }

  void _tearDown() {
    _guest
      ?..removeListener(_onFrame)
      ..dispose();
    _localHost?.dispose();
    unawaited(_loopback?.close());
    unawaited(_wire?.close());
    _guest = null;
    _localHost = null;
    _loopback = null;
    _wire = null;
    _controller.telemetry.clear();
  }

  void _switchTo(PongMode mode) {
    if (mode == _mode) return;
    setState(() {
      _tearDown();
      _mode = mode;
      _build();
    });
  }

  void _count({required bool inbound}) => _controller.telemetry.count(
    inbound ? PacketDirection.inbound : PacketDirection.outbound,
  );

  /// Plots the game's own round trip on the link meter, in place of the RSSI
  /// it shows the rest of the time.
  void _onFrame() {
    final guest = _guest;
    if (guest == null) return;
    if (guest.roundTrip case final trip?) {
      final millis = trip.inMilliseconds;
      _controller.telemetry.report(
        // The host publishes every 50 ms, so that much of the round trip is
        // the game's own pacing rather than the link's. The bands allow for
        // it: under 90 ms is as good as this protocol gets.
        grade: switch (millis) {
          < 90 => SignalGrade.strong,
          < 180 => SignalGrade.fair,
          _ => SignalGrade.weak,
        },
        caption: '$millis ms round trip',
        // 250 ms fills the strip; anything worse is unplayable anyway.
        level: 1 - (millis / 250).clamp(0.0, 1.0),
      );
    }
  }

  void _start() {
    _localHost?.start();
    _guest?.start();
  }

  @override
  Widget build(BuildContext context) {
    final guest = _guest;
    if (guest == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          _ModeSelector(mode: _mode, onChanged: _switchTo),
          if (_mode == PongMode.live && !_controller.isConnected)
            const _NeedsLink()
          else ...[
            Expanded(child: PongCourt(player: guest)),
            PongScoreBar(
              player: guest,
              onStart: _start,
              status: (state) => _status(guest, state),
            ),
          ],
        ],
      ),
    );
  }

  String _status(PongGuest guest, GameState? state) {
    if (!guest.peerPresent) {
      return 'Waiting for the host. Nothing has arrived on TX yet.';
    }
    if (state == null) return 'Connected. Press Serve to open a rally.';
    if (state.scoreOf(guest.side) >= pongWinningScore) return 'You win.';
    if (state.scoreOf(guest.side.opponent) >= pongWinningScore) {
      return 'The host wins.';
    }
    if (guest.isAuto) return 'Watching. Both paddles are playing themselves.';
    return 'Slide the track below the court, or drag anywhere on the court.';
  }
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.mode, required this.onChanged});

  final PongMode mode;
  final ValueChanged<PongMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        SegmentedButton<PongMode>(
          segments: [
            for (final option in PongMode.values)
              ButtonSegment(value: option, label: Text(option.label)),
          ],
          selected: {mode},
          showSelectedIcon: false,
          onSelectionChanged: (selection) => onChanged(selection.first),
        ),
        Text(mode.blurb, style: context.texts.bodySmall),
      ],
    );
  }
}

class _NeedsLink extends StatelessWidget {
  const _NeedsLink();

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Two-device mode needs a connection. Find the peripheral example '
            'on the Link page and connect to it, then come back.',
            textAlign: TextAlign.center,
            style: context.texts.bodyMedium,
          ),
        ),
      ),
    );
  }
}
