// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'report_catalog_field.dart';

part 'report_catalog_object.g.dart';

@JsonSerializable()
class ReportCatalogObject {
  const ReportCatalogObject({
    required this.fields,
    required this.label,
    required this.name,
  });
  
  factory ReportCatalogObject.fromJson(Map<String, Object?> json) => _$ReportCatalogObjectFromJson(json);
  
  final List<ReportCatalogField> fields;
  final String label;
  final String name;

  Map<String, Object?> toJson() => _$ReportCatalogObjectToJson(this);
}
