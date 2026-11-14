// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'column_pair.dart';

part 'import_mapping.g.dart';

/// A saved column mapping.
@JsonSerializable()
class ImportMapping {
  const ImportMapping({
    required this.columns,
    required this.createdAt,
    required this.entity,
    required this.id,
    required this.name,
    required this.updatedAt,
  });
  
  factory ImportMapping.fromJson(Map<String, Object?> json) => _$ImportMappingFromJson(json);
  
  final List<ColumnPair> columns;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  final String entity;
  final String id;
  final String name;
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  Map<String, Object?> toJson() => _$ImportMappingToJson(this);
}
