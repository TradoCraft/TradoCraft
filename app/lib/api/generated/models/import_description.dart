// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'column.dart';

part 'import_description.g.dart';

/// The serialisable description of an importable entity: what a later admin endpoint lists.
@JsonSerializable()
class ImportDescription {
  const ImportDescription({
    required this.auditEntity,
    required this.columns,
    required this.fileStem,
    required this.key,
    required this.keyColumn,
  });
  
  factory ImportDescription.fromJson(Map<String, Object?> json) => _$ImportDescriptionFromJson(json);
  
  /// Name of the entity in audit events (`customer`, `product`).
  @JsonKey(name: 'audit_entity')
  final String auditEntity;
  final List<Column> columns;

  /// File stem of an export and name of its sheet.
  @JsonKey(name: 'file_stem')
  final String fileStem;

  /// Stable key of the entity (`customers`, `products`).
  final String key;

  /// The column that identifies a record; upserts match on it.
  @JsonKey(name: 'key_column')
  final String keyColumn;

  Map<String, Object?> toJson() => _$ImportDescriptionToJson(this);
}
