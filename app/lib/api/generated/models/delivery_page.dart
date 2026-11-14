// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'delivery_summary.dart';

part 'delivery_page.g.dart';

@JsonSerializable()
class DeliveryPage {
  const DeliveryPage({
    required this.items,
    required this.total,
  });
  
  factory DeliveryPage.fromJson(Map<String, Object?> json) => _$DeliveryPageFromJson(json);
  
  final List<DeliverySummary> items;
  final int total;

  Map<String, Object?> toJson() => _$DeliveryPageToJson(this);
}
