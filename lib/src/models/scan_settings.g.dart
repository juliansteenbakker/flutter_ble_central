// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'scan_settings.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ScanSettings _$ScanSettingsFromJson(Map<String, dynamic> json) => ScanSettings(
      scanMode: $enumDecodeNullable(_$ScanModeEnumMap, json['scanMode']) ??
          ScanMode.scanModeLowLatency,
      reportDelay: json['reportDelay'] as int?,
      numOfMatches: json['numOfMatches'] as int?,
      legacyMode: json['legacyMode'] as bool?,
      phy: $enumDecodeNullable(_$PhyEnumMap, json['phy']),
    );

Map<String, dynamic> _$ScanSettingsToJson(ScanSettings instance) =>
    <String, dynamic>{
      'scanMode': _$ScanModeEnumMap[instance.scanMode]!,
      'reportDelay': instance.reportDelay,
      'numOfMatches': instance.numOfMatches,
      'legacyMode': instance.legacyMode,
      'phy': _$PhyEnumMap[instance.phy],
    };

const _$ScanModeEnumMap = {
  ScanMode.scanModeOpportunistic: -1,
  ScanMode.scanModeLowPower: 0,
  ScanMode.scanModeBalanced: 1,
  ScanMode.scanModeLowLatency: 2,
};

const _$PhyEnumMap = {
  Phy.phyLe1M: 1,
  Phy.phyLe2M: 2,
  Phy.phyLeCoded: 3,
  Phy.phyLeAllSupported: 4,
};
