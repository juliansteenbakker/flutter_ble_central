import 'dart:convert';

import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_ble_central/flutter_ble_central.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final FlutterBleCentral bleCentral = FlutterBleCentral();

  late final Stream<String> scanResultStream;

  var i = 0;
  @override
  void initState() {
    super.initState();
    initPlatformState();
    bleCentral.onScanResult.listen((event) {
      i++;
      debugPrint('FLUTTER $i rssi ${event.rssi} manudata ${event.scanRecord?.manufacturerSpecificData}');
    });
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initPlatformState() async {
    // If the widget was removed from the tree while the asynchronous platform
    // message was in flight, we want to discard the reply rather than calling
    // setState to update our non-existent appearance.
    if (!mounted) return;
  }

  bool isscanning = false;

  Future<void> _toggleScan() async {
    if (isscanning) {
      await bleCentral.stop();
      isscanning = false;
    } else {
      await bleCentral.start();
      isscanning = true;
    }
  }

  Future<void> _requestPermissions() async {
    // await Permission.bluetooth.shouldShowRequestRationale;

    // if ()

    final Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetooth,
      // Permission.bluetoothAdvertise,
      // Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
    ].request();
    for (final status in statuses.keys) {
      if (statuses[status] == PermissionStatus.granted) {
        debugPrint('$status permission granted');
      } else if (statuses[status] == PermissionStatus.denied) {
        debugPrint(
          '$status denied. Show a dialog with a reason and again ask for the permission.',);
      } else if (statuses[status] == PermissionStatus.permanentlyDenied) {
        debugPrint(
          '$status permanently denied. Take the user to the settings page.',);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Flutter BLE Central Example'),
        ),
        body: Center(
          child: Column(
            children: [
              const CircularProgressIndicator(),
              // StreamBuilder(
              //   stream: bleCentral.onScanResult,
              //   initialData: '',
              //   builder:
              //       (BuildContext context, AsyncSnapshot<dynamic> snapshot) {
              //     return Text('Packet: ${snapshot.data}');
              //   },),
              MaterialButton(
                onPressed: _toggleScan,
                child: Text(
                  'Toggle advertising',
                  style: Theme.of(context)
                      .primaryTextTheme
                      .button!
                      .copyWith(color: Colors.blue),
                ),),
              MaterialButton(
                onPressed: _requestPermissions,
                child: Text(
                  'Request Permissions',
                  style: Theme.of(context)
                      .primaryTextTheme
                      .button!
                      .copyWith(color: Colors.blue),
                ),),
            ],
          ),
        ),
      ),
    );
  }
}
