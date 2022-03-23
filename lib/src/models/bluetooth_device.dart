import 'package:json_annotation/json_annotation.dart';

part 'bluetooth_device.g.dart';

@JsonSerializable()
class BluetoothDevice {
  final String address;

  BluetoothDevice({required this.address});

  factory BluetoothDevice.fromJson(Map<String, dynamic> json) => _$BluetoothDeviceFromJson(json);

  Map<String, dynamic> toJson() => _$BluetoothDeviceToJson(this);
}