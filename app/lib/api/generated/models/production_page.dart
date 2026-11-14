// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'production_summary.dart';

part 'production_page.g.dart';

@JsonSerializable()
class ProductionPage {
  const ProductionPage({
    required this.items,
    required this.total,
  });
  
  factory ProductionPage.fromJson(Map<String, Object?> json) => _$ProductionPageFromJson(json);
  
  final List<ProductionSummary> items;
  final int total;

  Map<String, Object?> toJson() => _$ProductionPageToJson(this);
}
