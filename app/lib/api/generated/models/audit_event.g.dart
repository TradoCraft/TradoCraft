// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'audit_event.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AuditEvent _$AuditEventFromJson(Map<String, dynamic> json) => AuditEvent(
  action: json['action'] as String,
  data: json['data'],
  entity: json['entity'] as String,
  entityId: json['entity_id'] as String,
  id: (json['id'] as num).toInt(),
  occurredAt: DateTime.parse(json['occurred_at'] as String),
  userEmail: json['user_email'] as String?,
  userId: json['user_id'] as String?,
  userName: json['user_name'] as String?,
);

Map<String, dynamic> _$AuditEventToJson(AuditEvent instance) =>
    <String, dynamic>{
      'action': instance.action,
      'data': instance.data,
      'entity': instance.entity,
      'entity_id': instance.entityId,
      'id': instance.id,
      'occurred_at': instance.occurredAt.toIso8601String(),
      'user_email': ?instance.userEmail,
      'user_id': ?instance.userId,
      'user_name': ?instance.userName,
    };
