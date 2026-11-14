// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'sales_warning.g.dart';

/// A hint about a line that never blocks anything.
@JsonSerializable()
class SalesWarning {
  const SalesWarning({
    required this.details,
    required this.kind,
    required this.message,
    required this.productCode,
  });
  
  factory SalesWarning.fromJson(Map<String, Object?> json) => _$SalesWarningFromJson(json);
  
  /// Machine-readable details: `status` (incompatible | needs_external_supply | unknown_grid),.
  /// `country_code`, `supported` and `available` profiles. For `incompatible_products`:.
  /// `product_codes` (the pair), `note` and `relation_id`.
  final dynamic details;

  /// power_grid | incompatible_products
  final String kind;
  final String message;
  @JsonKey(name: 'product_code')
  final String productCode;

  Map<String, Object?> toJson() => _$SalesWarningToJson(this);
}
