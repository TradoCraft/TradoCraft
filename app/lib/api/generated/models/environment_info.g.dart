// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'environment_info.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

EnvironmentInfo _$EnvironmentInfoFromJson(Map<String, dynamic> json) =>
    EnvironmentInfo(
      dbName: json['db_name'] as String,
      instanceId: json['instance_id'] as String,
      kind: EnvKind.fromJson(json['kind'] as String),
      name: json['name'] as String,
      version: json['version'] as String,
    );

Map<String, dynamic> _$EnvironmentInfoToJson(EnvironmentInfo instance) =>
    <String, dynamic>{
      'db_name': instance.dbName,
      'instance_id': instance.instanceId,
      'kind': instance.kind,
      'name': instance.name,
      'version': instance.version,
    };
