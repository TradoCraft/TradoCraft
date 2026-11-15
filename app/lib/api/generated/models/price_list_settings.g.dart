// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'price_list_settings.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PriceListSettings _$PriceListSettingsFromJson(Map<String, dynamic> json) =>
    PriceListSettings(
      accentColor: json['accent_color'] as String? ?? '#1f4e79',
      currencySymbol: json['currency_symbol'] as String? ?? '',
      footerText: json['footer_text'] as String? ?? '',
      showLogo: json['show_logo'] as bool? ?? true,
      showUnit: json['show_unit'] as bool? ?? true,
    );

Map<String, dynamic> _$PriceListSettingsToJson(PriceListSettings instance) =>
    <String, dynamic>{
      'accent_color': instance.accentColor,
      'currency_symbol': instance.currencySymbol,
      'footer_text': instance.footerText,
      'show_logo': instance.showLogo,
      'show_unit': instance.showUnit,
    };
