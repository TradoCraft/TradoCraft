// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'helpdesk_report_spec.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

HelpdeskReportSpec _$HelpdeskReportSpecFromJson(Map<String, dynamic> json) =>
    HelpdeskReportSpec(
      period: json['period'] as String,
      table: json['table'] as String,
      category: json['category'] as String?,
      group: json['group'] as String?,
      ownerId: json['owner_id'] as String?,
      teamId: json['team_id'] as String?,
    );

Map<String, dynamic> _$HelpdeskReportSpecToJson(HelpdeskReportSpec instance) =>
    <String, dynamic>{
      'category': ?instance.category,
      'group': ?instance.group,
      'owner_id': ?instance.ownerId,
      'period': instance.period,
      'table': instance.table,
      'team_id': ?instance.teamId,
    };
