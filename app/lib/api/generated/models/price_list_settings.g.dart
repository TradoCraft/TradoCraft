// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'price_list_settings.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PriceListSettings _$PriceListSettingsFromJson(
  Map<String, dynamic> json,
) => PriceListSettings(
  accentColor: json['accent_color'] as String? ?? '#1f4e79',
  currencySymbol: json['currency_symbol'] as String? ?? '',
  footerText: json['footer_text'] as String? ?? '',
  importGroupLevels: (json['import_group_levels'] as num?)?.toInt() ?? 2,
  importShortPosition: json['import_short_position'] == null
      ? ImportShortPosition.shallowerGroup
      : ImportShortPosition.fromJson(json['import_short_position'] as String),
  importTitleConflict: json['import_title_conflict'] == null
      ? ImportTitleConflict.lowestPosition
      : ImportTitleConflict.fromJson(json['import_title_conflict'] as String),
  showLogo: json['show_logo'] as bool? ?? true,
  showUnit: json['show_unit'] as bool? ?? true,
);

Map<String, dynamic> _$PriceListSettingsToJson(PriceListSettings instance) =>
    <String, dynamic>{
      'accent_color': instance.accentColor,
      'currency_symbol': instance.currencySymbol,
      'footer_text': instance.footerText,
      'import_group_levels': instance.importGroupLevels,
      'import_short_position': instance.importShortPosition,
      'import_title_conflict': instance.importTitleConflict,
      'show_logo': instance.showLogo,
      'show_unit': instance.showUnit,
    };
