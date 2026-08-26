/// The physical layer a connection runs on.
///
/// The values are Android's `BluetoothDevice.PHY_LE_*` constants, which is what
/// crosses the channel. This is the connection counterpart of `Phy`, which
/// covers scanning and has an all-supported entry that a connection cannot use.
enum GattPhy {
  /// 1 Mbit/s, which every BLE device supports.
  le1M(1),

  /// 2 Mbit/s, on Bluetooth 5 and above. Faster, at shorter range.
  le2M(2),

  /// Long range with error correction, on Bluetooth 5 and above. Slower.
  leCoded(3);

  const GattPhy(this.value);

  /// The value the platform sends and expects.
  final int value;

  /// The PHY [value] stands for, or [GattPhy.le1M] for anything else.
  static GattPhy fromValue(int value) {
    for (final phy in GattPhy.values) {
      if (phy.value == value) return phy;
    }
    return GattPhy.le1M;
  }
}

/// The coding to prefer on [GattPhy.leCoded].
enum PhyOption {
  /// Let the controller choose.
  noPreferred(0),

  /// 500 kbit/s.
  s2(1),

  /// 125 kbit/s, the longest range.
  s8(2);

  const PhyOption(this.value);

  /// The value the platform expects.
  final int value;
}
