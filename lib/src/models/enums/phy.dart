import 'package:json_annotation/json_annotation.dart';

/// Set the Physical Layer to use during this scan.
/// This is used only if ScanSettings.Builder#setLegacy is set to false.
/// BluetoothAdapter.isLeCodedPhySupported() may be used to check
/// whether LE Coded phy is supported.
/// Selecting an unsupported phy will result in failure to start scan.

/// Physical Layer enum for BLE scanning
enum Phy {
  /// 1M PHY
  @JsonValue(1)
  phyLe1M,

  /// 2M PHY
  @JsonValue(2)
  phyLe2M,

  /// LE Coded PHY
  @JsonValue(3)
  phyLeCoded,

  /// All supported PHYs
  @JsonValue(4)
  phyLeAllSupported,
}
