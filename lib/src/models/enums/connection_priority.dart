/// How eagerly the connection should be serviced.
///
/// A shorter interval means lower latency and higher throughput at the cost of
/// power. The values are Android's `BluetoothGatt.CONNECTION_PRIORITY_*`
/// constants, which is what crosses the channel.
enum ConnectionPriority {
  /// The shortest interval the peripheral will accept. Costs the most power.
  high(0),

  /// The default, between [high] and [lowPower].
  balanced(1),

  /// The longest interval. Costs the least power, and is the slowest.
  lowPower(2);

  const ConnectionPriority(this.value);

  /// The value the platform expects.
  final int value;
}
