// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'suggestion_reason.dart';

part 'suggestion.g.dart';

@JsonSerializable()
class Suggestion {
  const Suggestion({
    required this.becauseOfCode,
    required this.note,
    required this.productCode,
    required this.productId,
    required this.productName,
    required this.reason,
    this.confidence,
    this.strength,
  });
  
  factory Suggestion.fromJson(Map<String, Object?> json) => _$SuggestionFromJson(json);
  
  /// The product of the set that triggered the suggestion.
  @JsonKey(name: 'because_of_code')
  final String becauseOfCode;

  /// 0 to 1, share of the orders with the other product that also contain this one.
  @JsonKey(includeIfNull: false)
  final double? confidence;

  /// Note of the manual rule.
  final String note;
  @JsonKey(name: 'product_code')
  final String productCode;
  @JsonKey(name: 'product_id')
  final String productId;
  @JsonKey(name: 'product_name')
  final String productName;
  final SuggestionReason reason;

  /// 1 to 100, from the manual rule.
  @JsonKey(includeIfNull: false)
  final int? strength;

  Map<String, Object?> toJson() => _$SuggestionToJson(this);
}
