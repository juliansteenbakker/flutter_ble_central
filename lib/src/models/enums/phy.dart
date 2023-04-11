import 'package:json_annotation/json_annotation.dart';

///Set the Physical Layer to use during this scan.
/// This is used only if ScanSettings.Builder#setLegacy is set to false.
/// BluetoothAdapter.isLeCodedPhySupported() may be used to check whether
/// LE Coded phy is supported by calling BluetoothAdapter.isLeCodedPhySupported().
/// Selecting an unsupported phy will result in failure to start scan.

enum Phy {
  @JsonValue(1)
  phyLe1M,
  @JsonValue(2)
  phyLe2M,
  @JsonValue(3)
  phyLeCoded,
  @JsonValue(4)
  phyLeAllSupported
}
