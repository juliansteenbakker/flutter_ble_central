/*
 * Copyright (c) 2026. Julian Steenbakker.
 * All rights reserved. Use of this source code is governed by a
 * BSD-style license that can be found in the LICENSE file.
 */

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ble_central/flutter_ble_central.dart';
import 'package:flutter_ble_central_example/central_controller.dart';
import 'package:flutter_ble_central_example/shell/shell.dart';

/// Everything you can do to a peripheral once you are connected to it.
///
/// The calls a platform does not serve stay on the page, greyed and labelled,
/// so the page doubles as the support matrix.
class DataPage extends StatefulWidget {
  /// Creates the page over [controller].
  const DataPage({required this.controller, super.key});

  /// The one controller the app runs on.
  final CentralController controller;

  @override
  State<DataPage> createState() => _DataPageState();
}

class _DataPageState extends State<DataPage> {
  final _payload = TextEditingController(text: '01 02 03');
  var _withoutResponse = false;

  CentralController get _controller => widget.controller;

  @override
  void dispose() {
    _payload.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final bytes = parseHexBytes(_payload.text);
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter hex bytes, such as 01 02 03')),
      );
      return;
    }
    await _controller.write(bytes, withoutResponse: _withoutResponse);
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.isConnected) {
      return const _NoLink();
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      children: [
        _exchange(context),
        const SizedBox(height: 12),
        _connection(),
        const SizedBox(height: 12),
        _descriptors(context),
        const SizedBox(height: 12),
        _pairing(),
        const SizedBox(height: 12),
        _radio(),
        const SizedBox(height: 12),
        _reliableWrite(),
        const SizedBox(height: 12),
        _services(context),
      ],
    );
  }

  Widget _exchange(BuildContext context) {
    final tokens = context.tokens;
    return Panel(
      label: 'EXCHANGE',
      footnote:
          "Writes go to the peripheral's RX characteristic and arrive "
          'on its onDataReceived stream. What it notifies on TX arrives here.',
      children: [
        Text(
          'TX  ${_controller.tx?.uuid ?? 'none'}\n'
          'RX  ${_controller.rx?.uuid ?? 'none'}',
          style: tokens.readoutDense,
        ),
        TextField(
          controller: _payload,
          style: tokens.readout,
          decoration: const InputDecoration(labelText: 'PAYLOAD, HEX BYTES'),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F ,]')),
          ],
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: _withoutResponse,
          onChanged: (value) => setState(() => _withoutResponse = value),
          title: Text(
            'Write without response',
            style: context.texts.labelLarge,
          ),
          subtitle: Text(
            'Skips the ATT acknowledgement. Faster, and the peripheral cannot '
            'refuse it.',
            style: context.texts.bodySmall,
          ),
        ),
        Row(
          spacing: 12,
          children: [
            Expanded(
              child: FilledButton(
                onPressed: _controller.rx == null ? null : _send,
                child: const Text('Write to RX'),
              ),
            ),
            Expanded(
              child: OutlinedButton(
                onPressed: _controller.tx == null ? null : _controller.readTx,
                child: const Text('Read TX'),
              ),
            ),
          ],
        ),
        const Divider(),
        _TrafficLog(controller: _controller),
      ],
    );
  }

  /// The descriptors on the characteristic this app subscribes to.
  ///
  /// Every notifying characteristic carries a Client Characteristic
  /// Configuration descriptor; it is the flag that
  /// `setCharacteristicNotification` writes, so reading it back is how you
  /// check that a subscription took.
  Widget _descriptors(BuildContext context) {
    final descriptors = _controller.tx?.descriptors ?? const <GattDescriptor>[];
    return Panel(
      label: 'DESCRIPTORS',
      footnote: descriptors.isEmpty
          ? 'None were discovered on TX, so these act on the Client '
                'Characteristic Configuration by uuid.'
          : null,
      children: [
        if (descriptors.isNotEmpty)
          Text(
            descriptors.map((d) => d.uuid).join('\n'),
            style: context.tokens.readoutDense,
          ),
        ActionRow(
          icon: Icons.notifications_active,
          title: 'Subscribe to TX',
          subtitle: 'Writes 01 00 to the configuration descriptor',
          onTap: () => _controller.setNotifications(enable: true),
        ),
        ActionRow(
          icon: Icons.notifications_off,
          title: 'Unsubscribe from TX',
          onTap: () => _controller.setNotifications(enable: false),
        ),
        ActionRow(
          icon: Icons.visibility,
          title: 'Read the configuration descriptor',
          subtitle: '01 00 means notifications, 02 00 indications',
          onTap: () => _controller.readTxDescriptor(_clientConfigurationUuid),
        ),
        ActionRow(
          icon: Icons.edit,
          title: 'Write 01 00 to it',
          subtitle: 'The long way round to what Subscribe does',
          onTap: () => _controller.writeTxDescriptor(
            _clientConfigurationUuid,
            Uint8List.fromList([0x01, 0x00]),
          ),
        ),
      ],
    );
  }

  Widget _connection() {
    return Panel(
      label: 'CONNECTION',
      children: [
        ActionRow(
          icon: Icons.straighten,
          title: 'Request MTU 517',
          subtitle: 'Android chooses; the others report what was negotiated',
          onTap: () => _controller.requestMtu(517),
        ),
        ActionRow(
          icon: Icons.network_check,
          title: 'Read link RSSI',
          subtitle: 'The strength of this connection, not of an advertisement',
          onTap: _controller.readRssi,
          unavailable: _unless(_Support.rssi),
        ),
        ActionRow(
          icon: Icons.help_outline,
          title: 'Read connection state',
          subtitle: 'Ask the platform rather than trust the stream',
          onTap: _controller.readConnectionState,
        ),
        ActionRow(
          icon: Icons.speed,
          title: 'Connection priority: high',
          subtitle:
              'An 11.25 to 15 ms interval on Android. What the game '
              'wants.',
          onTap: () => _controller.setPriority(ConnectionPriority.high),
          unavailable: _unless(_Support.connectionPriority),
        ),
        ActionRow(
          icon: Icons.battery_saver,
          title: 'Connection priority: balanced',
          subtitle: 'Back to the default interval',
          onTap: () => _controller.setPriority(ConnectionPriority.balanced),
          unavailable: _unless(_Support.connectionPriority),
        ),
      ],
    );
  }

  Widget _pairing() {
    return Panel(
      label: 'PAIRING',
      footnote:
          'Pairing needs someone to answer a system dialog, so these '
          'return as soon as the request is in. The outcome arrives on '
          'onBondStateChanged.',
      children: [
        Readout(
          label: 'BOND',
          value: _controller.bondState?.name ?? 'not read',
        ),
        ActionRow(
          icon: Icons.link,
          title: 'Pair',
          onTap: _controller.createBond,
          unavailable: _unless(_Support.bonding),
        ),
        ActionRow(
          icon: Icons.link_off,
          title: 'Unpair',
          onTap: _controller.removeBond,
          unavailable: _unless(_Support.bonding),
        ),
        ActionRow(
          icon: Icons.fingerprint,
          title: 'Read bond state',
          onTap: _controller.readBondState,
          unavailable: _unless(_Support.bonding),
        ),
      ],
    );
  }

  Widget _radio() {
    return Panel(
      label: 'RADIO',
      children: [
        ActionRow(
          icon: Icons.podcasts,
          title: 'Prefer 2M PHY',
          subtitle: 'Twice the symbol rate, at shorter range. Android 8.0 up.',
          onTap: () => _controller.setPreferredPhy(GattPhy.le2M),
          unavailable: _unless(_Support.phy),
        ),
        ActionRow(
          icon: Icons.podcasts,
          title: 'Prefer 1M PHY',
          onTap: () => _controller.setPreferredPhy(GattPhy.le1M),
          unavailable: _unless(_Support.phy),
        ),
        ActionRow(
          icon: Icons.visibility,
          title: 'Read PHY',
          subtitle: 'What the controller and the peripheral actually agreed on',
          onTap: _controller.readPhy,
          unavailable: _unless(_Support.phy),
        ),
      ],
    );
  }

  Widget _reliableWrite() {
    return Panel(
      label: 'RELIABLE WRITE',
      footnote:
          'Writes between begin and execute are queued on the peripheral '
          'and echoed back for checking before they take effect.',
      children: [
        ActionRow(
          icon: Icons.play_arrow,
          title: 'Begin',
          onTap: _controller.beginReliableWrite,
          unavailable: _unless(_Support.reliableWrite),
        ),
        ActionRow(
          icon: Icons.check,
          title: 'Execute',
          onTap: _controller.executeReliableWrite,
          unavailable: _unless(_Support.reliableWrite),
        ),
        ActionRow(
          icon: Icons.undo,
          title: 'Abort',
          onTap: _controller.abortReliableWrite,
          unavailable: _unless(_Support.reliableWrite),
        ),
      ],
    );
  }

  Widget _services(BuildContext context) {
    return Panel(
      label: 'DISCOVERED',
      children: [
        for (final service in _controller.services) ...[
          Text(service.uuid, style: context.tokens.readout),
          for (final characteristic
              in service.characteristics ?? const <GattCharacteristic>[])
            Padding(
              padding: const EdgeInsets.only(left: 12, top: 2),
              child: Text(
                '${characteristic.uuid}  '
                '${_properties(characteristic.properties)}',
                style: context.tokens.readoutDense,
              ),
            ),
        ],
      ],
    );
  }

  /// The properties a characteristic carries, as the short names the BLE
  /// specification uses.
  String _properties(GattCharacteristicProperties properties) {
    return <String>[
      if (properties.read) 'R',
      if (properties.write) 'W',
      if (properties.writeWithoutResponse) 'w',
      if (properties.notify) 'N',
      if (properties.indicate) 'I',
      if (properties.broadcast) 'B',
    ].join();
  }

  /// Why a call cannot run here, or null when it can.
  String? _unless(Set<TargetPlatform> supported) =>
      supported.contains(defaultTargetPlatform)
      ? null
      : 'Not supported on ${defaultTargetPlatform.name}';
}

/// The Client Characteristic Configuration descriptor, which every notifying
/// characteristic carries. It is the same uuid on every peripheral.
const _clientConfigurationUuid = '00002902-0000-1000-8000-00805f9b34fb';

/// Which platforms serve each optional call, from the plugin's README.
///
/// The page reads this to decide what to grey out, so the support matrix has
/// one home rather than being repeated in every row.
abstract final class _Support {
  /// `readRssi` works everywhere but Windows, which has no WinRT equivalent.
  static const Set<TargetPlatform> rssi = {
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.macOS,
  };

  /// Core Bluetooth has no pairing API at all.
  static const Set<TargetPlatform> bonding = {
    TargetPlatform.android,
    TargetPlatform.windows,
  };

  static const Set<TargetPlatform> phy = {TargetPlatform.android};
  static const Set<TargetPlatform> connectionPriority = {
    TargetPlatform.android,
  };
  static const Set<TargetPlatform> reliableWrite = {TargetPlatform.android};
}

class _TrafficLog extends StatelessWidget {
  const _TrafficLog({required this.controller});

  final CentralController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final traffic = controller.traffic;
    if (traffic.isEmpty) {
      return Text(
        'Nothing has crossed the link yet.',
        style: context.texts.bodySmall,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 4,
      children: [
        for (final packet in traffic.take(12))
          Row(
            spacing: 8,
            children: [
              Text(
                switch (packet.direction) {
                  PacketDirection.outbound => '↑',
                  PacketDirection.inbound => '↓',
                },
                style: tokens.readoutDense.copyWith(
                  color: packet.direction == PacketDirection.outbound
                      ? tokens.role.hue
                      : tokens.ink,
                ),
              ),
              Expanded(
                child: Text(
                  formatHexBytes(packet.bytes),
                  style: tokens.readout,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text('${packet.bytes.length} B', style: tokens.readoutDense),
            ],
          ),
      ],
    );
  }
}

class _NoLink extends StatelessWidget {
  const _NoLink();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          'Connect to a peripheral on the Link page and everything you can do '
          'to it appears here.',
          textAlign: TextAlign.center,
          style: context.texts.bodyMedium,
        ),
      ),
    );
  }
}
