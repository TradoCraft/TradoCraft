// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'report_field_type.dart';

part 'report_catalog_field.g.dart';

@JsonSerializable()
class ReportCatalogField {
  const ReportCatalogField({
    required this.countOnly,
    required this.label,
    required this.name,
    required this.type,
  });
  
  factory ReportCatalogField.fromJson(Map<String, Object?> json) => _$ReportCatalogFieldFromJson(json);
  
  /// Only the number of records can be shown for this field.
  @JsonKey(name: 'count_only')
  final bool countOnly;
  final String label;

  /// Qualified name to use in a definition, e.g. `quotation.total`.
  final String name;
  final ReportFieldType type;

  Map<String, Object?> toJson() => _$ReportCatalogFieldToJson(this);
}
