// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'order_summary.dart';

part 'order_page.g.dart';

@JsonSerializable()
class OrderPage {
  const OrderPage({
    required this.items,
    required this.total,
  });
  
  factory OrderPage.fromJson(Map<String, Object?> json) => _$OrderPageFromJson(json);
  
  final List<OrderSummary> items;
  final int total;

  Map<String, Object?> toJson() => _$OrderPageToJson(this);
}
