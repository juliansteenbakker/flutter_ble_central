/*
 * Copyright (c) 2026. Julian Steenbakker.
 * All rights reserved. Use of this source code is governed by a
 * BSD-style license that can be found in the LICENSE file.
 */

import 'package:flutter/material.dart';
import 'package:flutter_ble_central/flutter_ble_central.dart';
import 'package:flutter_ble_central_example/central_controller.dart';
import 'package:flutter_ble_central_example/shell/shell.dart';

/// Find a peripheral and connect to it. The app's primary job.
class LinkPage extends StatelessWidget {
  /// Creates the page over [controller].
  const LinkPage({required this.controller, super.key});

  /// The one controller the app runs on.
  final CentralController controller;

  @override
  Widget build(BuildContext context) {
    final devices = controller.devices;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      children: [
        if (controller.address != null) ...[
          _ConnectionPanel(controller: controller),
          const SizedBox(height: 12),
        ],
        _ScanPanel(controller: controller),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 4, 2, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'IN RANGE',
                  style: context.tokens.panelLabel,
                ),
              ),
              Text(
                '${devices.length} of ${controller.devicesSeen}',
                style: context.tokens.readoutDense,
              ),
            ],
          ),
        ),
        if (devices.isEmpty)
          _EmptyList(controller: controller)
        else
          for (final result in devices)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _DeviceRow(controller: controller, result: result),
            ),
      ],
    );
  }
}

class _ScanPanel extends StatelessWidget {
  const _ScanPanel({required this.controller});

  final CentralController controller;

  @override
  Widget build(BuildContext context) {
    final scanning = controller.isScanning;
    return Panel(
      label: 'SCAN',
      trailing: StateChip(
        label: scanning ? 'running' : 'stopped',
        grade: scanning ? SignalGrade.strong : SignalGrade.none,
        pulsing: scanning,
      ),
      footnote:
          'Scan settings apply on Android only. Everywhere else Core '
          'Bluetooth and WinRT choose for themselves.',
      children: [
        Row(
          spacing: 12,
          children: [
            Expanded(
              child: FilledButton(
                onPressed: scanning ? null : controller.startScan,
                child: const Text('Start scan'),
              ),
            ),
            Expanded(
              child: OutlinedButton(
                onPressed: scanning ? controller.stopScan : null,
                child: const Text('Stop'),
              ),
            ),
          ],
        ),
        ReadoutRow([
          Readout(label: 'ADVERTISEMENTS', value: '${controller.packetsSeen}'),
          Readout(label: 'DEVICES', value: '${controller.devicesSeen}'),
        ]),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: controller.onlyPeripheralExample,
          onChanged: (value) => controller.onlyPeripheralExample = value,
          title: Text(
            'Only the peripheral example',
            style: context.texts.labelLarge,
          ),
          subtitle: Text(
            'Hides everything not advertising '
            '${shortUuid(peripheralServiceUuid)}',
            style: context.texts.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _ConnectionPanel extends StatelessWidget {
  const _ConnectionPanel({required this.controller});

  final CentralController controller;

  @override
  Widget build(BuildContext context) {
    final connected = controller.isConnected;
    return Panel(
      label: 'LINK',
      trailing: StateChip(
        label: controller.connectionState.name,
        grade: connected ? SignalGrade.strong : SignalGrade.fair,
        pulsing: !connected,
      ),
      children: [
        Readout(
          label: 'PEER',
          value: controller.peerName ?? controller.address ?? '—',
          large: true,
        ),
        Text(controller.address ?? '', style: context.tokens.readoutDense),
        ReadoutRow([
          Readout(
            label: 'SERVICES',
            value: '${controller.services.length}',
          ),
          Readout(
            label: 'MTU',
            value: controller.mtu?.toString() ?? '—',
          ),
          Readout(
            label: 'RSSI',
            value: controller.linkRssi == null
                ? '—'
                : '${controller.linkRssi} dBm',
            tint: SignalGrade.fromRssi(controller.linkRssi).color,
          ),
        ]),
        OutlinedButton(
          onPressed: controller.disconnect,
          child: const Text('Disconnect'),
        ),
      ],
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({required this.controller, required this.result});

  final CentralController controller;
  final ScanResult result;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final address = result.device?.address;
    final rssi = result.rssi;
    final grade = SignalGrade.fromRssi(rssi);
    final servesExample = (result.scanRecord?.serviceUuids ?? const []).any(
      (uuid) => uuid?.toLowerCase() == peripheralServiceUuid,
    );
    final busy = controller.address != null;

    return Material(
      color: tokens.panel,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: tokens.hairline),
        borderRadius: const BorderRadius.all(Radius.circular(8)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: busy || address == null
            ? null
            : () => controller.connect(address),
        borderRadius: const BorderRadius.all(Radius.circular(8)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            spacing: 12,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      spacing: 6,
                      children: [
                        Flexible(
                          child: Text(
                            result.scanRecord?.deviceName ?? 'Unnamed',
                            style: context.texts.titleMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (servesExample) const Lamp(color: Color(0xFF2FBF71)),
                      ],
                    ),
                    Text(address ?? '—', style: tokens.readoutDense),
                  ],
                ),
              ),
              _SignalBars(grade: grade),
              SizedBox(
                width: 62,
                child: Text(
                  rssi == null ? '—' : '$rssi dBm',
                  textAlign: TextAlign.right,
                  style: tokens.readout.copyWith(color: grade.color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Four bars, lit up to the grade. The same ramp the meter uses.
class _SignalBars extends StatelessWidget {
  const _SignalBars({required this.grade});

  final SignalGrade grade;

  @override
  Widget build(BuildContext context) {
    final lit = switch (grade) {
      SignalGrade.strong => 3,
      SignalGrade.fair => 2,
      SignalGrade.weak => 1,
      SignalGrade.none => 0,
    };
    return Row(
      spacing: 2,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var bar = 0; bar < 3; bar++)
          Container(
            width: 3,
            height: 6.0 + bar * 4,
            color: bar < lit ? grade.color : context.tokens.hairline,
          ),
      ],
    );
  }
}

class _EmptyList extends StatelessWidget {
  const _EmptyList({required this.controller});

  final CentralController controller;

  @override
  Widget build(BuildContext context) {
    final message = switch (controller) {
      _ when controller.onlyPeripheralExample && controller.devicesSeen > 0 =>
        'None of the ${controller.devicesSeen} devices in range is serving '
            'the example service. Turn the filter off to see them all.',
      _ when controller.isScanning => 'Listening. Nothing has advertised yet.',
      _ => 'Start a scan to see what is in range.',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 8),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: context.texts.bodySmall,
      ),
    );
  }
}
