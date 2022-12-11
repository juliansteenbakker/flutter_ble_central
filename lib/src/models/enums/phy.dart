///Set the Physical Layer to use during this scan.
/// This is used only if ScanSettings.Builder#setLegacy is set to false.
/// BluetoothAdapter.isLeCodedPhySupported() may be used to check whether
/// LE Coded phy is supported by calling BluetoothAdapter.isLeCodedPhySupported().
/// Selecting an unsupported phy will result in failure to start scan.
enum Phy {
  phyLe1M,
  phyLeCoded,
  phyLeAllSupported
}
