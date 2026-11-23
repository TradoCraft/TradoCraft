// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'company_settings_input.g.dart';

/// Company-wide presentation settings managed by an administrator.
@JsonSerializable()
class CompanySettingsInput {
  const CompanySettingsInput({
    required this.quotationSingleLineItems,
    this.autosaveMinutes,
  });
  
  factory CompanySettingsInput.fromJson(Map<String, Object?> json) => _$CompanySettingsInputFromJson(json);
  
  /// Draft autosave interval in minutes (0 = disabled, 1..=120; default 5).
  @JsonKey(includeIfNull: false,name: 'autosave_minutes')
  final int? autosaveMinutes;

  /// Render quotation items on a single line (remarks in a dialog) instead of two lines.
  @JsonKey(name: 'quotation_single_line_items')
  final bool quotationSingleLineItems;

  Map<String, Object?> toJson() => _$CompanySettingsInputToJson(this);
}
