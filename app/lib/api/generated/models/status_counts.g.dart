// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'status_counts.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

StatusCounts _$StatusCountsFromJson(Map<String, dynamic> json) => StatusCounts(
  suitable: (json['suitable'] as num).toInt(),
  unknown: (json['unknown'] as num).toInt(),
  unsuitable: (json['unsuitable'] as num).toInt(),
);

Map<String, dynamic> _$StatusCountsToJson(StatusCounts instance) =>
    <String, dynamic>{
      'suitable': instance.suitable,
      'unknown': instance.unknown,
      'unsuitable': instance.unsuitable,
    };
