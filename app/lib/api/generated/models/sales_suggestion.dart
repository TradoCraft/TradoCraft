// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'sales_suggestion.g.dart';

/// A product worth adding to the quotation or order. Never blocking, never added automatically.
@JsonSerializable()
class SalesSuggestion {
  const SalesSuggestion({
    required this.becauseOfCode,
    required this.note,
    required this.productCode,
    required this.productId,
    required this.productName,
    required this.reason,
    this.confidence,
    this.strength,
  });
  
  factory SalesSuggestion.fromJson(Map<String, Object?> json) => _$SalesSuggestionFromJson(json);
  
  /// The product on the quotation that triggered the suggestion.
  @JsonKey(name: 'because_of_code')
  final String becauseOfCode;

  /// 0 to 1, for `often_bought_together`.
  @JsonKey(includeIfNull: false)
  final double? confidence;
  final String note;
  @JsonKey(name: 'product_code')
  final String productCode;
  @JsonKey(name: 'product_id')
  final String productId;
  @JsonKey(name: 'product_name')
  final String productName;

  /// rule | often_bought_together
  final String reason;

  /// 1 to 100, for `rule`.
  @JsonKey(includeIfNull: false)
  final int? strength;

  Map<String, Object?> toJson() => _$SalesSuggestionToJson(this);
}
