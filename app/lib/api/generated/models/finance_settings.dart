// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'finance_settings.g.dart';

/// The company's finance settings.
@JsonSerializable()
class FinanceSettings {
  const FinanceSettings({
    required this.priceTolerancePct,
    required this.quantityTolerancePct,
    this.updatedAt,
  });
  
  factory FinanceSettings.fromJson(Map<String, Object?> json) => _$FinanceSettingsFromJson(json);
  
  /// Price difference (percent of the order price) that is still a match.
  @JsonKey(name: 'price_tolerance_pct')
  final String priceTolerancePct;

  /// Extra quantity (percent of the ordered quantity) that may be invoiced.
  @JsonKey(name: 'quantity_tolerance_pct')
  final String quantityTolerancePct;

  /// When the settings were last saved; `None` while the defaults apply.
  @JsonKey(includeIfNull: false,name: 'updated_at')
  final DateTime? updatedAt;

  Map<String, Object?> toJson() => _$FinanceSettingsToJson(this);
}
