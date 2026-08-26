/// Whether this device is paired with a peripheral.
///
/// The values are Android's `BluetoothDevice.BOND_*` constants, which is what
/// crosses the channel, so they are not the enum's index.
enum BondState {
  /// Not paired.
  none(10),

  /// Pairing is in progress.
  bonding(11),

  /// Paired.
  bonded(12);

  const BondState(this.value);

  /// The value the platform sends.
  final int value;

  /// The state [value] stands for, or [BondState.none] for anything else.
  static BondState fromValue(int value) {
    for (final state in BondState.values) {
      if (state.value == value) return state;
    }
    return BondState.none;
  }
}
