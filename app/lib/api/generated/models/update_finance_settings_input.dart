// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'update_finance_settings_input.g.dart';

/// Payload to change the settings; omitted fields keep their value.
@JsonSerializable()
class UpdateFinanceSettingsInput {
  const UpdateFinanceSettingsInput({
    this.priceTolerancePct,
    this.quantityTolerancePct,
  });
  
  factory UpdateFinanceSettingsInput.fromJson(Map<String, Object?> json) => _$UpdateFinanceSettingsInputFromJson(json);
  
  /// New price tolerance in percent (0 to 100).
  @JsonKey(includeIfNull: false,name: 'price_tolerance_pct')
  final String? priceTolerancePct;

  /// New quantity tolerance in percent (0 to 100).
  @JsonKey(includeIfNull: false,name: 'quantity_tolerance_pct')
  final String? quantityTolerancePct;

  Map<String, Object?> toJson() => _$UpdateFinanceSettingsInputToJson(this);
}
