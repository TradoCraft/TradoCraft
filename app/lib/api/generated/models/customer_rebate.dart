// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'customer_rebate.g.dart';

@JsonSerializable()
class CustomerRebate {
  const CustomerRebate({
    required this.createdAt,
    required this.customerId,
    required this.id,
    required this.notes,
    required this.percent,
    required this.scope,
    this.familyCode,
    this.familyId,
    this.productCode,
    this.productId,
    this.validFrom,
    this.validTo,
  });
  
  factory CustomerRebate.fromJson(Map<String, Object?> json) => _$CustomerRebateFromJson(json);
  
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @JsonKey(name: 'customer_id')
  final String customerId;
  @JsonKey(includeIfNull: false,name: 'family_code')
  final String? familyCode;
  @JsonKey(includeIfNull: false,name: 'family_id')
  final String? familyId;
  final String id;
  final String notes;
  final String percent;
  @JsonKey(includeIfNull: false,name: 'product_code')
  final String? productCode;
  @JsonKey(includeIfNull: false,name: 'product_id')
  final String? productId;

  /// product | family
  final String scope;
  @JsonKey(includeIfNull: false,name: 'valid_from')
  final DateTime? validFrom;
  @JsonKey(includeIfNull: false,name: 'valid_to')
  final DateTime? validTo;

  Map<String, Object?> toJson() => _$CustomerRebateToJson(this);
}
