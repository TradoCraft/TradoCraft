// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'report_catalog_link.dart';
import 'report_catalog_object.dart';

part 'report_catalog.g.dart';

@JsonSerializable()
class ReportCatalog {
  const ReportCatalog({
    required this.links,
    required this.objects,
  });
  
  factory ReportCatalog.fromJson(Map<String, Object?> json) => _$ReportCatalogFromJson(json);
  
  /// Pairs of objects that can be joined in one report.
  final List<ReportCatalogLink> links;

  /// The objects the user may read.
  final List<ReportCatalogObject> objects;

  Map<String, Object?> toJson() => _$ReportCatalogToJson(this);
}
