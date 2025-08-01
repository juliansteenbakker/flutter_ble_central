import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_ble_central/flutter_ble_central.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  Map<String, ScanResult> devices = {};
  bool isScanning = false;
  int packetsFound = 0;
  int? queue = 0;

  @override
  void initState() {
    super.initState();

    Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        debugPrint('Packets found: $packetsFound, in queue $queue');
      });
    });

    FlutterBleCentral().onScanError?.listen((event) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error: ${AndroidError.values[event]}, code: $event',
          ),
        ),
      );
      debugPrint('Error: ${AndroidError.values[event]}, code: $event');
    });

    FlutterBleCentral().onScanResult.listen((event) {
      packetsFound++;
    });
  }

  Future<void> _requestPermissions() async {
    final hasPermission = await FlutterBleCentral().hasPermission();
    switch (hasPermission) {
      case BluetoothCentralState.denied:
        _messangerKey.currentState?.showSnackBar(
          const SnackBar(
            backgroundColor: Colors.red,
            content: Text(
              "We don't have permissions, requesting now!",
            ),
          ),
        );

        await _requestPermissions();
        break;
      default:
        _messangerKey.currentState?.showSnackBar(
          SnackBar(
            backgroundColor: Colors.green,
            content: Text(
              'State: $hasPermission!',
            ),
          ),
        );
        break;
    }
  }

  final _messangerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      showPerformanceOverlay: true,
      scaffoldMessengerKey: _messangerKey,
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Flutter BLE Central example'),
          actions: <Widget>[
            IconButton(
              onPressed: () => setState(() {
                FlutterBleCentral().stop();
              }),
              icon: const Icon(Icons.lock_reset),
            ),
            IconButton(
              onPressed: _requestPermissions,
              icon: const Icon(Icons.security),
            ),
            if (isScanning)
              IconButton(
                icon: const Icon(Icons.pause_circle_filled),
                onPressed: () => setState(() {
                  isScanning = false;
                  FlutterBleCentral().stop();
                }),
              )
            else
              IconButton(
                icon: const Icon(Icons.play_arrow),
                onPressed: () async {
                  final messenger = _messangerKey.currentState!;
                  final state = await FlutterBleCentral().start();
                  switch (state) {
                    case BluetoothCentralState.ready:
                    case BluetoothCentralState.granted:
                      setState(() {
                        isScanning = true;
                        devices.clear();
                      });
                      break;
                    case BluetoothCentralState.denied:
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Bluetooth denied, we can ask again!',
                          ),
                        ),
                      );
                      break;
                    case BluetoothCentralState.permanentlyDenied:
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Bluetooth denied, we can NOT ask again!',
                          ),
                        ),
                      );
                      break;
                    case BluetoothCentralState.restricted:
                      // TODO: Handle this case.
                      break;
                    case BluetoothCentralState.limited:
                      // TODO: Handle this case.
                      break;
                    case BluetoothCentralState.turnedOff:
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Bluetooth turned off.',
                          ),
                        ),
                      );
                      break;
                    case BluetoothCentralState.unsupported:
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Bluetooth unsupported off.',
                          ),
                        ),
                      );
                      break;
                    case BluetoothCentralState.unknown:
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Unknown error..',
                          ),
                        ),
                      );
                      break;
                  }
                },
              ),
          ],
        ),
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              onPressed: () async {
                if (isScanning) {
                  FlutterBleCentral().stop();
                  isScanning = false;
                } else {
                  isScanning = true;
                  devices.clear();
                  FlutterBleCentral().start(
                    scanSettings: ScanSettings(
                      scanMode: ScanMode.scanModeLowLatency,
                    ),
                  );
                  await Future.delayed(
                    const Duration(
                      seconds: 30,
                    ),
                  );
                  FlutterBleCentral().stop();
                  isScanning = false;
                }
              },
              child: const Text('30 Seconds Test'),
            ),
            ElevatedButton(
              onPressed: () => FlutterBleCentral().openBluetoothSettings(),
              child: const Text('Bluetooth settings'),
            ),
            ElevatedButton(
              onPressed: () => FlutterBleCentral().openAppSettings(),
              child: const Text('App settings'),
            ),
            Text('Packets found: $packetsFound, in queue $queue'),
            CircularProgressIndicator(),
            ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.all(8),
              itemBuilder: (BuildContext context, int index) {
                final scanResult = devices.values.elementAt(index);
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.bluetooth),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              // Text(s),
                              Text('${scanResult.scanRecord?.deviceName}'),
                              Text('${scanResult.device?.address}'),
                              Text('RSSI: ${scanResult.rssi}'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
              separatorBuilder: (context, index) => const SizedBox(height: 5),
              itemCount: devices.length,
            ),
          ],
        ),
      ),
    );
  }
}
