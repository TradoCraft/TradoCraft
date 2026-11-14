// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'order_line_edit.g.dart';

@JsonSerializable()
class OrderLineEdit {
  const OrderLineEdit({
    required this.position,
    required this.quantity,
    this.description,
    this.lineDiscountPercent,
  });
  
  factory OrderLineEdit.fromJson(Map<String, Object?> json) => _$OrderLineEditFromJson(json);
  
  /// Replaces the description; empty keeps the current one.
  @JsonKey(includeIfNull: false)
  final String? description;
  @JsonKey(includeIfNull: false,name: 'line_discount_percent')
  final String? lineDiscountPercent;

  /// The position of the line in the current draft revision.
  final int position;
  final String quantity;

  Map<String, Object?> toJson() => _$OrderLineEditToJson(this);
}
