// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'audit_facets.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AuditFacets _$AuditFacetsFromJson(Map<String, dynamic> json) => AuditFacets(
  entities: (json['entities'] as List<dynamic>)
      .map((e) => e as String)
      .toList(),
);

Map<String, dynamic> _$AuditFacetsToJson(AuditFacets instance) =>
    <String, dynamic>{'entities': instance.entities};
