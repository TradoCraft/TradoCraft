// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'report_catalog_link.g.dart';

@JsonSerializable()
class ReportCatalogLink {
  const ReportCatalogLink({
    required this.a,
    required this.b,
  });
  
  factory ReportCatalogLink.fromJson(Map<String, Object?> json) => _$ReportCatalogLinkFromJson(json);
  
  final String a;
  final String b;

  Map<String, Object?> toJson() => _$ReportCatalogLinkToJson(this);
}
