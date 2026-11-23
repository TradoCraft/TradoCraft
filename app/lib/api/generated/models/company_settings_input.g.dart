// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'company_settings_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CompanySettingsInput _$CompanySettingsInputFromJson(
  Map<String, dynamic> json,
) => CompanySettingsInput(
  quotationSingleLineItems: json['quotation_single_line_items'] as bool,
  autosaveMinutes: (json['autosave_minutes'] as num?)?.toInt(),
);

Map<String, dynamic> _$CompanySettingsInputToJson(
  CompanySettingsInput instance,
) => <String, dynamic>{
  'autosave_minutes': ?instance.autosaveMinutes,
  'quotation_single_line_items': instance.quotationSingleLineItems,
};
