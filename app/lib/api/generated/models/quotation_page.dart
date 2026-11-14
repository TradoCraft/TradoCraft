// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'quotation_summary.dart';

part 'quotation_page.g.dart';

@JsonSerializable()
class QuotationPage {
  const QuotationPage({
    required this.items,
    required this.total,
  });
  
  factory QuotationPage.fromJson(Map<String, Object?> json) => _$QuotationPageFromJson(json);
  
  final List<QuotationSummary> items;
  final int total;

  Map<String, Object?> toJson() => _$QuotationPageToJson(this);
}
