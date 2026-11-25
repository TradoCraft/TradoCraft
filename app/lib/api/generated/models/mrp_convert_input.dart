// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'mrp_convert_input.g.dart';

@JsonSerializable()
class MrpConvertInput {
  const MrpConvertInput({
    this.divisionId,
    this.supplierId,
  });
  
  factory MrpConvertInput.fromJson(Map<String, Object?> json) => _$MrpConvertInputFromJson(json);
  
  /// For a production order: the division that builds it; defaults to the one that normally does.
  @JsonKey(includeIfNull: false,name: 'division_id')
  final String? divisionId;

  /// For a purchase: the supplier, when the proposal has none (the product has no preferred one).
  @JsonKey(includeIfNull: false,name: 'supplier_id')
  final String? supplierId;

  Map<String, Object?> toJson() => _$MrpConvertInputToJson(this);
}
