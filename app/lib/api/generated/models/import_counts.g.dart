// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'import_counts.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ImportCounts _$ImportCountsFromJson(Map<String, dynamic> json) => ImportCounts(
  bell: (json['bell'] as num).toInt(),
  bellGroup: (json['bell_group'] as num).toInt(),
  clockDial: (json['clock_dial'] as num).toInt(),
);

Map<String, dynamic> _$ImportCountsToJson(ImportCounts instance) =>
    <String, dynamic>{
      'bell': instance.bell,
      'bell_group': instance.bellGroup,
      'clock_dial': instance.clockDial,
    };
