// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'favorite_summary.g.dart';

/// One row of the list.
@JsonSerializable()
class FavoriteSummary {
  const FavoriteSummary({
    required this.id,
    required this.languages,
    required this.mainProductActive,
    required this.mainProductCode,
    required this.mainProductId,
    required this.mainProductName,
    required this.name,
    required this.optionCount,
    required this.updatedAt,
  });
  
  factory FavoriteSummary.fromJson(Map<String, Object?> json) => _$FavoriteSummaryFromJson(json);
  
  final String id;

  /// The languages (nl, fr, en, de, es) in which at least one customer remark exists.
  final List<String> languages;

  /// Whether the main product is still active.
  @JsonKey(name: 'main_product_active')
  final bool mainProductActive;
  @JsonKey(name: 'main_product_code')
  final String mainProductCode;
  @JsonKey(name: 'main_product_id')
  final String mainProductId;
  @JsonKey(name: 'main_product_name')
  final String mainProductName;
  final String name;

  /// The number of lines below the main item.
  @JsonKey(name: 'option_count')
  final int optionCount;
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  Map<String, Object?> toJson() => _$FavoriteSummaryToJson(this);
}
