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
    // final Map<Permission, PermissionStatus> statuses = await [
    //   Permission.bluetooth,
    //   Permission.bluetoothConnect,
    //   Permission.bluetoothScan,
    //   Permission.location,
    // ].request();
    // for (final status in statuses.keys) {
    //   if (statuses[status] == PermissionStatus.granted) {
    //     debugPrint('$status permission granted');
    //   } else if (statuses[status] == PermissionStatus.denied) {
    //     debugPrint(
    //       '$status denied. Show a dialog with a reason and again ask for the permission.',
    //     );
    //   } else if (statuses[status] == PermissionStatus.permanentlyDenied) {
    //     debugPrint(
    //       '$status permanently denied. Take the user to the settings page.',
    //     );
    //   }
    // }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Flutter BLE Central example'),
          actions: <Widget>[
            IconButton(
              onPressed: () => setState(() {
                packetsFound = 0;
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
                onPressed: () {
                  setState(() {
                    isScanning = true;
                    devices.clear();
                    FlutterBleCentral().start();
                  });
                },
              )
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
                    ),);
                    await Future.delayed(const Duration(
                      seconds: 30,
                    ),);
                    FlutterBleCentral().stop();
                    isScanning = false;
                  }
                },
                child: const Text('30 Seconds Test'),),
            Text('Packets found: $packetsFound, in queue $queue'),
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
