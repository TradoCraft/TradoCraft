// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'rebate_input.g.dart';

@JsonSerializable()
class RebateInput {
  const RebateInput({
    required this.percent,
    required this.scope,
    this.familyId,
    this.notes,
    this.productId,
    this.validFrom,
    this.validTo,
  });
  
  factory RebateInput.fromJson(Map<String, Object?> json) => _$RebateInputFromJson(json);
  
  @JsonKey(includeIfNull: false,name: 'family_id')
  final String? familyId;
  @JsonKey(includeIfNull: false)
  final String? notes;
  final String percent;
  @JsonKey(includeIfNull: false,name: 'product_id')
  final String? productId;

  /// product | family
  final String scope;
  @JsonKey(includeIfNull: false,name: 'valid_from')
  final DateTime? validFrom;
  @JsonKey(includeIfNull: false,name: 'valid_to')
  final DateTime? validTo;

  Map<String, Object?> toJson() => _$RebateInputToJson(this);
}
