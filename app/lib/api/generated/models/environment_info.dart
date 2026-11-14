// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'env_kind.dart';

part 'environment_info.g.dart';

/// The environment this API instance serves.
@JsonSerializable()
class EnvironmentInfo {
  const EnvironmentInfo({
    required this.dbName,
    required this.kind,
    required this.name,
    required this.version,
  });
  
  factory EnvironmentInfo.fromJson(Map<String, Object?> json) => _$EnvironmentInfoFromJson(json);
  
  /// Name of the database only; never host, user or password.
  @JsonKey(name: 'db_name')
  final String dbName;
  final EnvKind kind;

  /// Display name (`APP_ENV_NAME`, default: the database name).
  final String name;

  /// Version of the API.
  final String version;

  Map<String, Object?> toJson() => _$EnvironmentInfoToJson(this);
}
