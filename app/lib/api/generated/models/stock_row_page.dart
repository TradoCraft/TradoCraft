// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'stock_row.dart';

part 'stock_row_page.g.dart';

@JsonSerializable()
class StockRowPage {
  const StockRowPage({
    required this.items,
    required this.total,
  });
  
  factory StockRowPage.fromJson(Map<String, Object?> json) => _$StockRowPageFromJson(json);
  
  final List<StockRow> items;
  final int total;

  Map<String, Object?> toJson() => _$StockRowPageToJson(this);
}
