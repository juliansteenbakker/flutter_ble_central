// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'scan_settings.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ScanSettings _$ScanSettingsFromJson(Map<String, dynamic> json) => ScanSettings(
      scanMode: $enumDecodeNullable(_$ScanModeEnumMap, json['scanMode']),
      reportDelay: (json['reportDelay'] as num?)?.toInt(),
      callbackType: $enumDecodeNullable(
        _$CallbackTypeEnumMap,
        json['callbackType'],
      ),
      matchMode: $enumDecodeNullable(_$MatchModeEnumMap, json['matchMode']),
      numOfMatches:
          $enumDecodeNullable(_$MatchNumEnumMap, json['numOfMatches']),
      legacyMode: json['legacyMode'] as bool?,
      phy: $enumDecodeNullable(_$PhyEnumMap, json['phy']),
      useLightweightScanResult: json['useLightweightScanResult'] as bool?,
    );

Map<String, dynamic> _$ScanSettingsToJson(ScanSettings instance) =>
    <String, dynamic>{
      'scanMode': _$ScanModeEnumMap[instance.scanMode],
      'reportDelay': instance.reportDelay,
      'callbackType': _$CallbackTypeEnumMap[instance.callbackType],
      'matchMode': _$MatchModeEnumMap[instance.matchMode],
      'numOfMatches': _$MatchNumEnumMap[instance.numOfMatches],
      'legacyMode': instance.legacyMode,
      'phy': _$PhyEnumMap[instance.phy],
      'useLightweightScanResult': instance.useLightweightScanResult,
    };

const _$ScanModeEnumMap = {
  ScanMode.scanModeOpportunistic: -1,
  ScanMode.scanModeLowPower: 0,
  ScanMode.scanModeBalanced: 1,
  ScanMode.scanModeLowLatency: 2,
};

const _$CallbackTypeEnumMap = {
  CallbackType.allMatches: 1,
  CallbackType.firstMatch: 2,
  CallbackType.matchLost: 4,
  CallbackType.allMatchesAutoBatch: 8,
};

const _$MatchModeEnumMap = {MatchMode.aggressive: 1, MatchMode.sticky: 2};

const _$MatchNumEnumMap = {
  MatchNum.oneAdvertisement: 1,
  MatchNum.fewAdvertisement: 2,
  MatchNum.maxAdvertisement: 3,
};

const _$PhyEnumMap = {
  Phy.phyLe1M: 1,
  Phy.phyLe2M: 2,
  Phy.phyLeCoded: 3,
  Phy.phyLeAllSupported: 4,
};
