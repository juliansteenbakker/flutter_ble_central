/// Represents the connection state of a Bluetooth device.
///
/// Named for GATT rather than plainly `ConnectionState`, which would collide
/// with Flutter's own on every import of material.dart.
enum GattConnectionState {
  /// Device is disconnected
  disconnected,

  /// Device is connecting
  connecting,

  /// Device is connected
  connected,

  /// Device is disconnecting
  disconnecting,
}
