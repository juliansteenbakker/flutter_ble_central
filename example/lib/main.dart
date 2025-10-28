import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_ble_central/flutter_ble_central.dart';

void main() {
  runApp(const MyApp());
}

/// Example app demonstrating Flutter BLE Central functionality
class MyApp extends StatefulWidget {
  /// Creates the example app
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  final _ble = FlutterBleCentral();

  final Map<String, ScanResult> _devices = {};
  StreamSubscription<ScanResult>? _scanResultSub;
  StreamSubscription<int>? _scanErrorSub;

  bool _isScanning = false;
  int _packetsFound = 0;

  @override
  void initState() {
    super.initState();
    _ble.enableTimingStats = true; // Only for dev purposes
    _listenToScanStreams();
  }

  @override
  Future<void> dispose() async {
    await _scanResultSub?.cancel();
    await _scanErrorSub?.cancel();
    super.dispose();
  }

  void _listenToScanStreams() {
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

      // Only rebuild when scanning to keep UI smooth
      if (_isScanning) setState(() {});
    });
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

  Future<void> _checkPermission() async {
    final status = await _ble.hasPermission();
    _showSnackBar(
      'Permission status: ${status.name}',
      isError: status != BluetoothCentralState.granted,
    );
  }

  Future<void> _requestPermission() async {
    final status = await _ble.requestPermission();
    _showSnackBar(
      'Permission status: ${status.name}',
      isError: status != BluetoothCentralState.granted,
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
    setState(() {
      _isScanning = false;
    });
  }

  Future<void> _startScanFor30s() async {
    await _startScan();
    await Future<void>.delayed(const Duration(seconds: 30));
    await _stopScan();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: _messengerKey,
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Flutter BLE Central Example'),
          actions: [
            IconButton(
              icon: const Icon(Icons.security),
              tooltip: 'Request permission',
              onPressed: _requestPermission,
            ),
            IconButton(
              icon: const Icon(Icons.help_outline),
              tooltip: 'Check permission',
              onPressed: _checkPermission,
            ),
            if (_isScanning)
              IconButton(
                icon: const Icon(Icons.pause_circle_filled),
                tooltip: 'Stop scanning',
                onPressed: _stopScan,
              )
            else
              IconButton(
                icon: const Icon(Icons.play_arrow),
                tooltip: 'Start scanning',
                onPressed: _startScan,
              ),
          ],
        ),
        body: Column(
          children: [
            const SizedBox(height: 8),
            Text(
              'Packets found: $_packetsFound\nDevices: ${_devices.length}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: _startScanFor30s,
                  child: const Text('30s Test'),
                ),
                ElevatedButton(
                  onPressed: _ble.openBluetoothSettings,
                  child: const Text('Bluetooth Settings'),
                ),
                ElevatedButton(
                  onPressed: _ble.openAppSettings,
                  child: const Text('App Settings'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _devices.isEmpty
                  ? const Center(child: Text('No devices found yet'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(8),
                      itemCount: _devices.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final scanResult = _devices.values.elementAt(index);
                        final name =
                            scanResult.scanRecord?.deviceName ?? 'Unknown';
                        final address = scanResult.device?.address ?? 'N/A';
                        final rssi = scanResult.rssi ?? 0;

                        return Card(
                          child: ListTile(
                            leading: const Icon(Icons.bluetooth),
                            title: Text(name),
                            subtitle: Text('$address\nRSSI: $rssi'),
                            isThreeLine: true,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
