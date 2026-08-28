/*
 * Copyright (c) 2026. Julian Steenbakker.
 * All rights reserved. Use of this source code is governed by a
 * BSD-style license that can be found in the LICENSE file.
 */

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ble_central/flutter_ble_central.dart';
import 'package:flutter_ble_central_example/central_controller.dart';
import 'package:flutter_ble_central_example/shell/shell.dart';

/// Permissions, the adapter, and the settings the next scan runs with.
class SetupPage extends StatelessWidget {
  /// Creates the page over [controller].
  const SetupPage({required this.controller, super.key});

  /// The one controller the app runs on.
  final CentralController controller;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      children: [
        _ScanSettingsPanel(controller: controller),
        const SizedBox(height: 12),
        _PermissionPanel(controller: controller),
        const SizedBox(height: 12),
        _AdapterPanel(controller: controller),
      ],
    );
  }
}

/// The `ScanSettings` the plugin accepts.
///
/// Android is the only platform that reads any of it. Core Bluetooth and WinRT
/// scan the way they choose, so the panel says so rather than pretending the
/// controls do something everywhere.
class _ScanSettingsPanel extends StatelessWidget {
  const _ScanSettingsPanel({required this.controller});

  final CentralController controller;

  @override
  Widget build(BuildContext context) {
    final settings = controller.scanSettings;
    final android = defaultTargetPlatform == TargetPlatform.android;

    return Panel(
      label: 'SCAN SETTINGS',
      footnote: android
          ? 'Applied when the next scan starts. Stop and start to change a '
                'running one.'
          : 'Android reads these. This platform ignores them and scans the '
                'way it chooses.',
      children: [
        _Choice<ScanMode>(
          label: 'SCAN MODE',
          help: 'How hard the radio looks, traded against battery',
          value: settings.scanMode,
          values: ScanMode.values,
          enabled: android,
          onChanged: (mode) =>
              controller.scanSettings = _copy(settings, scanMode: () => mode),
        ),
        _Choice<CallbackType>(
          label: 'CALLBACK TYPE',
          help: 'Every advertisement, or only the first and last of each match',
          value: settings.callbackType,
          values: CallbackType.values,
          enabled: android,
          onChanged: (type) => controller.scanSettings = _copy(
            settings,
            callbackType: () => type,
          ),
        ),
        _Choice<MatchMode>(
          label: 'MATCH MODE',
          help: 'How strong a signal has to be before it counts as a match',
          value: settings.matchMode,
          values: MatchMode.values,
          enabled: android,
          onChanged: (mode) =>
              controller.scanSettings = _copy(settings, matchMode: () => mode),
        ),
        _Choice<MatchNum>(
          label: 'MATCHES PER FILTER',
          help: 'How many advertisers the hardware tracks at once',
          value: settings.numOfMatches,
          values: MatchNum.values,
          enabled: android,
          onChanged: (matches) => controller.scanSettings = _copy(
            settings,
            numOfMatches: () => matches,
          ),
        ),
        _Choice<Phy>(
          label: 'PHY',
          help: 'Which physical layer to scan on. Needs legacy mode off.',
          value: settings.phy,
          values: Phy.values,
          enabled: android,
          onChanged: (phy) =>
              controller.scanSettings = _copy(settings, phy: () => phy),
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: settings.legacyMode ?? true,
          onChanged: android
              ? (value) => controller.scanSettings = _copy(
                  settings,
                  legacyMode: () => value,
                )
              : null,
          title: Text('Legacy mode', style: context.texts.labelLarge),
          subtitle: Text(
            'On, the scanner only reports legacy advertisements. Off, it '
            'reports extended ones too.',
            style: context.texts.bodySmall,
          ),
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: settings.useLightweightScanResult ?? false,
          onChanged: (value) => controller.scanSettings = _copy(
            settings,
            useLightweightScanResult: () => value,
          ),
          title: Text('Lightweight results', style: context.texts.labelLarge),
          subtitle: Text(
            'Sends the address and RSSI only, skipping the parsed '
            'advertisement. Cheaper when a scan is busy.',
            style: context.texts.bodySmall,
          ),
        ),
      ],
    );
  }

  /// `ScanSettings` has no `copyWith`, and its fields are nullable, so each
  /// replacement is passed as a thunk to tell "leave alone" from "set null".
  ScanSettings _copy(
    ScanSettings settings, {
    ScanMode? Function()? scanMode,
    CallbackType? Function()? callbackType,
    MatchMode? Function()? matchMode,
    MatchNum? Function()? numOfMatches,
    Phy? Function()? phy,
    bool? Function()? legacyMode,
    bool? Function()? useLightweightScanResult,
  }) {
    return ScanSettings(
      scanMode: scanMode == null ? settings.scanMode : scanMode(),
      reportDelay: settings.reportDelay,
      callbackType: callbackType == null
          ? settings.callbackType
          : callbackType(),
      matchMode: matchMode == null ? settings.matchMode : matchMode(),
      numOfMatches: numOfMatches == null
          ? settings.numOfMatches
          : numOfMatches(),
      legacyMode: legacyMode == null ? settings.legacyMode : legacyMode(),
      phy: phy == null ? settings.phy : phy(),
      useLightweightScanResult: useLightweightScanResult == null
          ? settings.useLightweightScanResult
          : useLightweightScanResult(),
    );
  }
}

/// A labelled row of segmented choices, which reads better than a dropdown for
/// the three- and four-valued enums the scanner uses.
class _Choice<T extends Enum> extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.help,
    required this.value,
    required this.values,
    required this.onChanged,
    required this.enabled,
  });

  final String label;
  final String help;
  final T? value;
  final List<T> values;
  final ValueChanged<T> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 6,
      children: [
        Text(label, style: tokens.panelLabel),
        Text(help, style: context.texts.bodySmall),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final option in values)
              _Segment(
                label: option.name,
                selected: option == value,
                onTap: enabled ? () => onChanged(option) : null,
              ),
          ],
        ),
      ],
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final hue = tokens.role.hue;
    return Material(
      color: selected ? hue.withValues(alpha: 0.12) : Colors.transparent,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: selected ? hue : tokens.hairline),
        borderRadius: const BorderRadius.all(Radius.circular(4)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            label,
            style: tokens.readout.copyWith(
              color: onTap == null
                  ? tokens.inkMuted
                  : (selected ? hue : tokens.ink),
            ),
          ),
        ),
      ),
    );
  }
}

class _PermissionPanel extends StatelessWidget {
  const _PermissionPanel({required this.controller});

  final CentralController controller;

  @override
  Widget build(BuildContext context) {
    final apple =
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
    return Panel(
      label: 'PERMISSIONS',
      children: [
        ActionRow(
          icon: Icons.checklist,
          title: 'Run the access check',
          subtitle: 'Hardware, then permission, then power',
          onTap: () => ensureRadioReady(context, controller),
        ),
        ActionRow(
          icon: Icons.help_outline,
          title: 'Check permission',
          subtitle: 'Reports what is held without asking for anything',
          onTap: () async {
            final state = await controller.check();
            if (context.mounted) _report(context, 'Permission: ${state.label}');
          },
        ),
        ActionRow(
          icon: Icons.add_moderator,
          title: 'Request permission',
          onTap: () async {
            final state = await controller.request();
            if (context.mounted) _report(context, 'Permission: ${state.label}');
          },
          unavailable: apple
              ? 'Core Bluetooth asks on first use, not on request'
              : null,
        ),
        ActionRow(
          icon: Icons.app_settings_alt,
          title: 'Open app settings',
          onTap: controller.openAppSettings,
        ),
      ],
    );
  }
}

class _AdapterPanel extends StatelessWidget {
  const _AdapterPanel({required this.controller});

  final CentralController controller;

  @override
  Widget build(BuildContext context) {
    final apple =
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
    return Panel(
      label: 'ADAPTER',
      children: [
        Readout(label: 'STATE', value: controller.adapterState.name),
        ActionRow(
          icon: Icons.power_settings_new,
          title: 'Turn the radio on',
          onTap: () async {
            final on = await controller.powerOn();
            if (context.mounted) {
              _report(context, on ? 'Radio on' : 'The radio stayed off');
            }
          },
          unavailable: apple ? 'Apple does not let an app do this' : null,
        ),
        ActionRow(
          icon: Icons.settings_bluetooth,
          title: 'Open Bluetooth settings',
          onTap: controller.openRadioSettings,
        ),
        ActionRow(
          icon: Icons.hardware,
          title: 'Check hardware support',
          onTap: () async {
            final supported = await controller.isSupported;
            if (context.mounted) {
              _report(
                context,
                supported ? 'This device has a BLE radio' : 'No BLE radio',
              );
            }
          },
        ),
      ],
    );
  }
}

void _report(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(message)));
}
