/*
 * Copyright (c) 2022. Julian Steenbakker.
 * All rights reserved. Use of this source code is governed by a
 * BSD-style license that can be found in the LICENSE file.
 */

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_ble_central/flutter_ble_central.dart';

void main() => runApp(const FlutterBleCentralExample());

/// Example app for the flutter_ble_central plugin
class FlutterBleCentralExample extends StatefulWidget {
  /// Constructor for the example app of the flutter_ble_central plugin
  const FlutterBleCentralExample({super.key});

  @override
  State<FlutterBleCentralExample> createState() =>
      _FlutterBleCentralExampleState();
}

class _FlutterBleCentralExampleState extends State<FlutterBleCentralExample> {
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _ble = FlutterBleCentral();

  final Map<String, ScanResult> _devices = {};
  StreamSubscription<ScanResult>? _scanResultSub;
  StreamSubscription<int>? _scanErrorSub;
  StreamSubscription<CentralState>? _stateChangedSub;

  bool _isSupported = false;
  bool _isScanning = false;
  int _packetsFound = 0;
  CentralState _centralState = CentralState.unknown;

  @override
  void initState() {
    super.initState();
    _ble.enableTimingStats = true;
    _listenToStreams();
    unawaited(_initPlatformState());
  }

  @override
  void dispose() {
    unawaited(_scanResultSub?.cancel());
    unawaited(_scanErrorSub?.cancel());
    unawaited(_stateChangedSub?.cancel());
    super.dispose();
  }

  void _listenToStreams() {
    _scanErrorSub = _ble.onScanError?.listen((event) {
      final error = AndroidError.values[event];
      _showSnackBar('Scan error: $error (code $event)', isError: true);
    });

    _scanResultSub = _ble.onScanResult.listen((result) {
      _packetsFound++;

      final address = result.device?.address;
      if (address != null) {
        _devices[address] = result;
      }

      if (_isScanning) setState(() {});
    });

    _stateChangedSub = _ble.onPeripheralStateChanged.listen((state) {
      setState(() => _centralState = state);
    });
  }

  Future<void> _initPlatformState() async {
    final isSupported = await _ble.isSupported;
    setState(() => _isSupported = isSupported);

    if ((Platform.isWindows ||
            Platform.isAndroid ||
            Platform.isIOS ||
            Platform.isMacOS) &&
        mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _checkPermissions();
      });
    }
  }

  Future<void> _checkPermissions() async {
    // First check if BLE is supported
    final isSupported = await _ble.isSupported;
    if (!isSupported && mounted) {
      await _showUnsupportedDialog();
      return;
    }

    // Check permissions first (on Apple, we can't determine Bluetooth power
    // state until we have permission - state shows as unauthorized)
    final permission = await _ble.hasPermission();
    if (permission != BluetoothCentralState.granted && mounted) {
      final shouldContinue = await _showPermissionDialog(permission);
      if (shouldContinue != true) return;
    }

    // Now check if Bluetooth is powered on (after permission is granted)
    final isBluetoothOn = await _ble.isBluetoothOn;
    if (!isBluetoothOn && mounted) {
      await _showBluetoothOffDialog();
    }
  }

  Future<void> _showUnsupportedDialog() async {
    final navigatorContext = _navigatorKey.currentContext;
    if (navigatorContext == null) return;

    await showDialog<void>(
      context: navigatorContext,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          icon:
              const Icon(Icons.bluetooth_disabled, color: Colors.red, size: 48),
          title: const Text('Bluetooth Not Supported'),
          content: const Text(
            'This device does not support Bluetooth Low Energy (BLE) scanning.'
            '\n\n'
            'BLE central mode requires compatible hardware.',
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<bool?> _showPermissionDialog(
    BluetoothCentralState initialState,
  ) async {
    final navigatorContext = _navigatorKey.currentContext;
    if (navigatorContext == null) return false;

    return showDialog<bool>(
      context: navigatorContext,
      barrierDismissible: false,
      builder: (dialogContext) {
        return _PermissionDialog(
          initialState: initialState,
          onGranted: () {
            _messengerKey.currentState?.showSnackBar(
              const SnackBar(
                content: Text('Permission granted!'),
                backgroundColor: Colors.green,
              ),
            );
          },
        );
      },
    );
  }

  Future<bool?> _showBluetoothOffDialog() async {
    final navigatorContext = _navigatorKey.currentContext;
    if (navigatorContext == null) return false;

    return showDialog<bool>(
      context: navigatorContext,
      barrierDismissible: false,
      builder: (dialogContext) {
        return _BluetoothOffDialog(
          onEnabled: () {
            _messengerKey.currentState?.showSnackBar(
              const SnackBar(
                content: Text('Bluetooth enabled!'),
                backgroundColor: Colors.green,
              ),
            );
          },
        );
      },
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    _messengerKey.currentState
      ?..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red : Colors.green,
        ),
      );
  }

  Future<void> _startScan() async {
    final state = await _ble.start();

    switch (state) {
      case BluetoothCentralState.ready:
      case BluetoothCentralState.granted:
        setState(() {
          _isScanning = true;
          _devices.clear();
          _packetsFound = 0;
        });
      case BluetoothCentralState.denied:
        _showSnackBar('Bluetooth denied. You can ask again.', isError: true);
      case BluetoothCentralState.permanentlyDenied:
        _showSnackBar('Bluetooth permanently denied.', isError: true);
      case BluetoothCentralState.turnedOff:
        _showSnackBar('Bluetooth turned off.', isError: true);
      case BluetoothCentralState.unsupported:
        _showSnackBar('Bluetooth unsupported.', isError: true);
      case BluetoothCentralState.restricted:
        _showSnackBar('Bluetooth restricted.', isError: true);
      case BluetoothCentralState.limited:
        _showSnackBar('Bluetooth limited.', isError: true);
      case BluetoothCentralState.unknown:
        _showSnackBar('Bluetooth unavailable.', isError: true);
    }
  }

  Future<void> _stopScan() async {
    await _ble.stop();
    setState(() => _isScanning = false);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _messengerKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('BLE Central'),
          centerTitle: true,
        ),
        body: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Status Card
              Padding(
                padding: const EdgeInsets.all(16),
                child: _StatusCard(
                  isSupported: _isSupported,
                  centralState: _centralState,
                  isScanning: _isScanning,
                  packetsFound: _packetsFound,
                  devicesFound: _devices.length,
                ),
              ),

              // Scan Controls
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _SectionCard(
                  title: 'Scanning',
                  icon: Icons.bluetooth_searching,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _isScanning ? null : _startScan,
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('Start'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isScanning ? _stopScan : null,
                            icon: const Icon(Icons.stop),
                            label: const Text('Stop'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Bluetooth Controls
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _SectionCard(
                  title: 'Bluetooth',
                  icon: Icons.bluetooth,
                  children: [
                    _ActionTile(
                      icon: Icons.bluetooth_connected,
                      title: 'Enable Bluetooth',
                      subtitle: 'Turn on Bluetooth radio',
                      onTap: () async {
                        final enabled = await _ble.enableBluetooth();
                        _showSnackBar(
                          enabled
                              ? 'Bluetooth enabled!'
                              : 'Failed to enable Bluetooth',
                          isError: !enabled,
                        );
                      },
                    ),
                    _ActionTile(
                      icon: Icons.settings_bluetooth,
                      title: 'Bluetooth Settings',
                      subtitle: 'Open system Bluetooth settings',
                      onTap: _ble.openBluetoothSettings,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Permission Controls
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _SectionCard(
                  title: 'Permissions',
                  icon: Icons.security,
                  children: [
                    _ActionTile(
                      icon: Icons.check_circle_outline,
                      title: 'Check Permission',
                      subtitle: 'Verify current permission status',
                      onTap: () async {
                        final status = await _ble.hasPermission();
                        _showSnackBar(
                          'Permission: ${status.name}',
                          isError: status != BluetoothCentralState.granted,
                        );
                      },
                    ),
                    if (!Platform.isIOS && !Platform.isMacOS)
                      _ActionTile(
                        icon: Icons.add_circle_outline,
                        title: 'Request Permission',
                        subtitle: 'Request required permissions',
                        onTap: () async {
                          final status = await _ble.requestPermission();
                          _showSnackBar(
                            'Permission: ${status.name}',
                            isError: status != BluetoothCentralState.granted,
                          );
                        },
                      ),
                    _ActionTile(
                      icon: Icons.app_settings_alt,
                      title: 'App Settings',
                      subtitle: 'Open app settings',
                      onTap: _ble.openAppSettings,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Device List
              if (_devices.isEmpty)
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.bluetooth_searching,
                        size: 64,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _isScanning
                            ? 'Scanning for devices...'
                            : 'No devices found',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                      ),
                    ],
                  ),
                )
              else
                ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _devices.length,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemBuilder: (context, index) {
                    final scanResult = _devices.values.elementAt(index);
                    final name = scanResult.scanRecord?.deviceName ?? 'Unknown';
                    final address = scanResult.device?.address ?? 'N/A';
                    final rssi = scanResult.rssi ?? 0;

                    return Card(
                      child: ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color:
                                Theme.of(context).colorScheme.primaryContainer,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.bluetooth,
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                          ),
                        ),
                        title: Text(name),
                        subtitle: Text(address),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.signal_cellular_alt,
                              color: _getRssiColor(rssi),
                            ),
                            Text(
                              '$rssi dBm',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getRssiColor(int rssi) {
    if (rssi >= -50) return Colors.green;
    if (rssi >= -70) return Colors.orange;
    return Colors.red;
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.isSupported,
    required this.centralState,
    required this.isScanning,
    required this.packetsFound,
    required this.devicesFound,
  });
  final bool isSupported;
  final CentralState centralState;
  final bool isScanning;
  final int packetsFound;
  final int devicesFound;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (icon, color, label) = _getStateInfo(centralState, colorScheme);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isScanning ? Icons.bluetooth_searching : icon,
                size: 48,
                color: isScanning ? Colors.blue : color,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              isScanning ? 'Scanning' : label,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              centralState.name.toUpperCase(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
            ),
            const Divider(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _StatItem(
                  icon: Icons.devices,
                  label: 'Devices',
                  value: devicesFound.toString(),
                ),
                _StatItem(
                  icon: Icons.wifi_tethering,
                  label: 'Packets',
                  value: packetsFound.toString(),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isSupported ? Icons.check_circle : Icons.cancel,
                      size: 16,
                      color: isSupported ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isSupported ? 'Supported' : 'Not Supported',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  (IconData, Color, String) _getStateInfo(
    CentralState state,
    ColorScheme colorScheme,
  ) {
    return switch (state) {
      CentralState.idle => (Icons.bluetooth, colorScheme.primary, 'Ready'),
      CentralState.advertising => (
          Icons.broadcast_on_personal,
          Colors.green,
          'Advertising'
        ),
      CentralState.connected => (Icons.link, Colors.blue, 'Connected'),
      CentralState.poweredOff => (
          Icons.bluetooth_disabled,
          Colors.red,
          'Bluetooth Off'
        ),
      CentralState.unsupported => (
          Icons.error_outline,
          Colors.red,
          'Unsupported'
        ),
      CentralState.unauthorized => (Icons.lock, Colors.orange, 'Unauthorized'),
      CentralState.unknown => (
          Icons.help_outline,
          colorScheme.outline,
          'Unknown'
        ),
    };
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });
  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class _StepItem extends StatelessWidget {
  const _StepItem({required this.number, required this.text});
  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _PermissionDialog extends StatefulWidget {
  const _PermissionDialog({
    required this.onGranted,
    required this.initialState,
  });
  final VoidCallback onGranted;
  final BluetoothCentralState initialState;

  @override
  State<_PermissionDialog> createState() => _PermissionDialogState();
}

class _PermissionDialogState extends State<_PermissionDialog>
    with WidgetsBindingObserver {
  final _ble = FlutterBleCentral();
  bool _checkingPermission = false;
  bool _requesting = false;
  late BluetoothCentralState _permissionState;

  @override
  void initState() {
    super.initState();
    _permissionState = widget.initialState;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_checkPermissionAndClose());
    }
  }

  Future<void> _checkPermissionAndClose() async {
    if (_checkingPermission) return;
    _checkingPermission = true;

    final result = await _ble.hasPermission();
    if (result == BluetoothCentralState.granted && mounted) {
      widget.onGranted();
      Navigator.of(context).pop(true);
    } else if (mounted) {
      setState(() => _permissionState = result);
    }

    _checkingPermission = false;
  }

  Future<void> _requestPermission() async {
    if (_requesting) return;
    setState(() => _requesting = true);

    final result = await _ble.requestPermission();
    if (result == BluetoothCentralState.granted && mounted) {
      widget.onGranted();
      Navigator.of(context).pop(true);
    } else if (mounted) {
      setState(() {
        _requesting = false;
        _permissionState = result;
      });
    }
  }

  bool get _isPermanentlyDenied =>
      _permissionState == BluetoothCentralState.permanentlyDenied;

  @override
  Widget build(BuildContext context) {
    if (Platform.isAndroid) {
      return _buildAndroidDialog(context);
    } else if (Platform.isIOS || Platform.isMacOS) {
      return _buildAppleDialog(context);
    } else {
      return _buildWindowsDialog(context);
    }
  }

  Widget _buildAndroidDialog(BuildContext context) {
    return AlertDialog(
      icon: Icon(
        _isPermanentlyDenied ? Icons.block : Icons.bluetooth,
        color: _isPermanentlyDenied ? Colors.red : Colors.blue,
        size: 48,
      ),
      title: Text(
        _isPermanentlyDenied ? 'Permission Denied' : 'Permission Required',
      ),
      content: Text(
        _isPermanentlyDenied
            ? 'Bluetooth permission was denied. You can only grant permission '
                'through the app settings.\n\n'
                'Please open Settings and enable Bluetooth permissions for '
                'this app.'
            : 'BLE scanning requires Bluetooth permissions.\n\n'
                'Please grant the required permissions to continue.',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        if (_isPermanentlyDenied)
          FilledButton.icon(
            onPressed: _ble.openAppSettings,
            icon: const Icon(Icons.settings),
            label: const Text('Open Settings'),
          )
        else ...[
          OutlinedButton.icon(
            onPressed: _ble.openBluetoothSettings,
            icon: const Icon(Icons.settings),
            label: const Text('Settings'),
          ),
          FilledButton.icon(
            onPressed: _requesting ? null : _requestPermission,
            icon: _requesting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: const Text('Grant'),
          ),
        ],
      ],
    );
  }

  Widget _buildAppleDialog(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.bluetooth, color: Colors.blue, size: 48),
      title: const Text('Permission Required'),
      content: const Text(
        'BLE scanning requires Bluetooth permission.\n\n'
        'Please enable Bluetooth access for this app in System Settings.',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _ble.openBluetoothSettings,
          icon: const Icon(Icons.settings),
          label: const Text('Open Settings'),
        ),
      ],
    );
  }

  Widget _buildWindowsDialog(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.location_on, color: Colors.blue, size: 48),
      title: const Text('Permission Required'),
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('BLE scanning on Windows requires location permission.\n'),
          Text(
            'Please follow these steps:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 12),
          _StepItem(number: '1', text: 'Click "Open Settings" below'),
          _StepItem(number: '2', text: 'Scroll down and find:'),
          Padding(
            padding: EdgeInsets.only(left: 32, top: 4, bottom: 4),
            child: Text(
              '"Let desktop apps access your location"',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
          ),
          _StepItem(number: '3', text: 'Turn this switch ON'),
          _StepItem(number: '4', text: 'Return to this app'),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _ble.openAppSettings,
          icon: const Icon(Icons.settings),
          label: const Text('Open Settings'),
        ),
      ],
    );
  }
}

class _BluetoothOffDialog extends StatefulWidget {
  const _BluetoothOffDialog({required this.onEnabled});
  final VoidCallback onEnabled;

  @override
  State<_BluetoothOffDialog> createState() => _BluetoothOffDialogState();
}

class _BluetoothOffDialogState extends State<_BluetoothOffDialog>
    with WidgetsBindingObserver {
  final _ble = FlutterBleCentral();
  bool _checking = false;
  bool _enabling = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_checkBluetoothAndClose());
    }
  }

  Future<void> _checkBluetoothAndClose() async {
    if (_checking) return;
    _checking = true;

    final isOn = await _ble.isBluetoothOn;
    if (isOn && mounted) {
      widget.onEnabled();
      Navigator.of(context).pop(true);
    }

    _checking = false;
  }

  Future<void> _enableBluetooth() async {
    if (_enabling) return;
    setState(() => _enabling = true);

    final success = await _ble.enableBluetooth();
    if (success && mounted) {
      widget.onEnabled();
      Navigator.of(context).pop(true);
    } else if (mounted) {
      setState(() => _enabling = false);
    }
  }

  bool get _isApplePlatform => Platform.isIOS || Platform.isMacOS;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.bluetooth_disabled, color: Colors.red, size: 48),
      title: const Text('Bluetooth is Off'),
      content: Text(
        _isApplePlatform
            ? 'Bluetooth is currently turned off. BLE scanning requires '
                'Bluetooth to be enabled.\n\n'
                'Please enable Bluetooth in Settings.'
            : 'Bluetooth is currently turned off. BLE scanning requires '
                'Bluetooth to be enabled.\n\n'
                'Would you like to turn on Bluetooth?',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        if (_isApplePlatform)
          FilledButton.icon(
            onPressed: _ble.openBluetoothSettings,
            icon: const Icon(Icons.settings),
            label: const Text('Open Settings'),
          )
        else ...[
          OutlinedButton.icon(
            onPressed: _ble.openBluetoothSettings,
            icon: const Icon(Icons.settings),
            label: const Text('Settings'),
          ),
          FilledButton.icon(
            onPressed: _enabling ? null : _enableBluetooth,
            icon: _enabling
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.bluetooth),
            label: const Text('Turn On'),
          ),
        ],
      ],
    );
  }
}
