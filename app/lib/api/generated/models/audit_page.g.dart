// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'audit_page.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AuditPage _$AuditPageFromJson(Map<String, dynamic> json) => AuditPage(
  items: (json['items'] as List<dynamic>)
      .map((e) => AuditEvent.fromJson(e as Map<String, dynamic>))
      .toList(),
  nextBeforeId: (json['next_before_id'] as num?)?.toInt(),
);

Map<String, dynamic> _$AuditPageToJson(AuditPage instance) => <String, dynamic>{
  'items': instance.items,
  'next_before_id': ?instance.nextBeforeId,
};
