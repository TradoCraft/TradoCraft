// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'change_kind.dart';

part 'bulk_price_change_input.g.dart';

@JsonSerializable()
class BulkPriceChangeInput {
  const BulkPriceChangeInput({
    required this.kind,
    required this.validFrom,
    required this.value,
    this.familyId,
    this.productIds,
    this.rounding,
    this.zoneIds,
  });
  
  factory BulkPriceChangeInput.fromJson(Map<String, Object?> json) => _$BulkPriceChangeInputFromJson(json);
  
  /// Limit to one product family.
  @JsonKey(includeIfNull: false,name: 'family_id')
  final String? familyId;
  final ChangeKind kind;

  /// Limit to these products (combined with the family filter, if any).
  @JsonKey(includeIfNull: false,name: 'product_ids')
  final List<String>? productIds;

  /// Round new prices to a multiple of this step, e.g. 0.01, 0.05 or 1. Default 0.01.
  @JsonKey(includeIfNull: false)
  final String? rounding;

  /// First day of the new prices; today or later.
  @JsonKey(name: 'valid_from')
  final DateTime validFrom;
  final String value;

  /// Zones to change; empty = all zones of the active company.
  @JsonKey(includeIfNull: false,name: 'zone_ids')
  final List<String>? zoneIds;

  Map<String, Object?> toJson() => _$BulkPriceChangeInputToJson(this);
}
