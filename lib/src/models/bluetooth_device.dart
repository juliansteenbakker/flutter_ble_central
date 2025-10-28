import 'package:json_annotation/json_annotation.dart';

part 'bluetooth_device.g.dart';

/// Represents a Bluetooth device
@JsonSerializable()
class BluetoothDevice {
  /// Creates a BluetoothDevice
  BluetoothDevice({
    required this.address,
    this.bondState,
    this.name,
    this.type,
  });

  /// Creates a BluetoothDevice from JSON
  factory BluetoothDevice.fromJson(Map<String, dynamic> json) =>
      _$BluetoothDeviceFromJson(json);

  /// The Bluetooth device address
  final String address;

  /// The bond state of the device
  final int? bondState;

  /// The name of the device
  final String? name;

  /// The type of the device
  final int? type;

  /// Converts this BluetoothDevice to JSON
  Map<String, dynamic> toJson() => _$BluetoothDeviceToJson(this);
}
