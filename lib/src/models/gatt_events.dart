import 'dart:typed_data';

import 'package:flutter_ble_central/src/models/enums/bond_state.dart';
import 'package:flutter_ble_central/src/models/enums/gatt_connection_state.dart';

/// A change in the link to a peripheral, from
/// `FlutterBleCentral.onConnectionStateChanged`.
class ConnectionStateChange {
  /// Creates a connection state change.
  const ConnectionStateChange({required this.address, required this.state});

  /// Reads the change out of the map the platform sends.
  factory ConnectionStateChange.fromPlatform(Map<Object?, Object?> event) {
    final state = event['state'] as int? ?? 0;
    return ConnectionStateChange(
      address: event['address'] as String? ?? '',
      state: state < GattConnectionState.values.length
          ? GattConnectionState.values[state]
          : GattConnectionState.disconnected,
    );
  }

  /// The peripheral the change is about.
  final String address;

  /// The state the link is now in.
  final GattConnectionState state;

  @override
  String toString() => 'ConnectionStateChange($address, ${state.name})';
}

/// A value a peripheral notified, from
/// `FlutterBleCentral.onCharacteristicValueChanged`.
class CharacteristicValue {
  /// Creates a characteristic value.
  const CharacteristicValue({
    required this.address,
    required this.serviceUuid,
    required this.characteristicUuid,
    required this.value,
  });

  /// Reads the value out of the map the platform sends.
  factory CharacteristicValue.fromPlatform(Map<Object?, Object?> event) {
    final value = event['value'];
    return CharacteristicValue(
      address: event['address'] as String? ?? '',
      serviceUuid: event['serviceUuid'] as String? ?? '',
      characteristicUuid: event['characteristicUuid'] as String? ?? '',
      value: value is Uint8List
          ? value
          : Uint8List.fromList((value as List? ?? []).cast<int>()),
    );
  }

  /// The peripheral the value came from.
  final String address;

  /// The service holding the characteristic.
  final String serviceUuid;

  /// The characteristic that changed.
  final String characteristicUuid;

  /// The bytes it now holds.
  final Uint8List value;

  @override
  String toString() => 'CharacteristicValue($address, $characteristicUuid, '
      '${value.length} bytes)';
}

/// A change in whether this device is paired with a peripheral, from
/// `FlutterBleCentral.onBondStateChanged`.
class BondStateChange {
  /// Creates a bond state change.
  const BondStateChange({required this.address, required this.state});

  /// Reads the change out of the map the platform sends.
  factory BondStateChange.fromPlatform(Map<Object?, Object?> event) {
    return BondStateChange(
      address: event['address'] as String? ?? '',
      state: BondState.fromValue(event['bondState'] as int? ?? 10),
    );
  }

  /// The peripheral the change is about.
  final String address;

  /// Whether it is now paired.
  final BondState state;

  @override
  String toString() => 'BondStateChange($address, ${state.name})';
}
