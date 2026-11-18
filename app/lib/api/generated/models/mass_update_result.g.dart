// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mass_update_result.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MassUpdateResult _$MassUpdateResultFromJson(Map<String, dynamic> json) =>
    MassUpdateResult(
      dryRun: json['dry_run'] as bool,
      items: (json['items'] as List<dynamic>)
          .map((e) => MassUpdateItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      updated: (json['updated'] as num).toInt(),
    );

Map<String, dynamic> _$MassUpdateResultToJson(MassUpdateResult instance) =>
    <String, dynamic>{
      'dry_run': instance.dryRun,
      'items': instance.items,
      'updated': instance.updated,
    };
