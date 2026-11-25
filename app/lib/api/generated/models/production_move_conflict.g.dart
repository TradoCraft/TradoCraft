// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'production_move_conflict.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ProductionMoveConflict _$ProductionMoveConflictFromJson(
  Map<String, dynamic> json,
) => ProductionMoveConflict(
  kind: json['kind'] as String,
  messageKey: json['message_key'] as String,
  severity: json['severity'] as String,
  day: json['day'] == null ? null : DateTime.parse(json['day'] as String),
);

Map<String, dynamic> _$ProductionMoveConflictToJson(
  ProductionMoveConflict instance,
) => <String, dynamic>{
  'day': ?instance.day?.toIso8601String(),
  'kind': instance.kind,
  'message_key': instance.messageKey,
  'severity': instance.severity,
};
