/*
 * Copyright (c) 2026. Julian Steenbakker.
 * All rights reserved. Use of this source code is governed by a
 * BSD-style license that can be found in the LICENSE file.
 */

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_ble_central_example/central_controller.dart';
import 'package:flutter_ble_central_example/pong/pong.dart';

/// Carries the game over a real GATT link, as the guest.
///
/// Writes go to the peripheral's RX characteristic without waiting for an
/// acknowledgement, and what it notifies on TX comes back. That is the same
/// pipe the Data page uses; the game just puts structured bytes through it.
final class CentralPongTransport implements PongTransport {
  /// Creates a transport over the controller's own connection.
  CentralPongTransport(this._controller) {
    _controller.onInbound = _onBytes;
    _controller.isGameRunning = true;
  }

  final CentralController _controller;
  final _inbox = StreamController<PongMessage>.broadcast();

  @override
  Stream<PongMessage> get incoming => _inbox.stream;

  @override
  bool get isReady => _controller.isConnected && _controller.rx != null;

  @override
  Future<void> send(PongMessage message) async {
    if (!isReady) return;
    await _controller.write(message.encode(), withoutResponse: true);
  }

  void _onBytes(Uint8List bytes) {
    // Anything at all can arrive on the characteristic, including a payload
    // typed by hand on the Data page. Messages that are not ours are dropped.
    if (PongMessage.decode(bytes) case final message?) _inbox.add(message);
  }

  @override
  Future<void> close() async {
    _controller
      ..onInbound = null
      ..isGameRunning = false;
    await _inbox.close();
  }
}
