// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'price_list_settings.g.dart';

/// Presentation of a list. No row means defaults apply to every key.
@JsonSerializable()
class PriceListSettings {
  const PriceListSettings({
    this.accentColor = '#1f4e79',
    this.currencySymbol = '',
    this.footerText = '',
    this.showLogo = true,
    this.showUnit = true,
  });
  
  factory PriceListSettings.fromJson(Map<String, Object?> json) => _$PriceListSettingsFromJson(json);
  
  /// Colour of the title and chapter headings, `#rrggbb`.
  @JsonKey(name: 'accent_color')
  final String accentColor;

  /// Printed before prices; empty uses the company currency (EUR as the euro sign).
  @JsonKey(name: 'currency_symbol')
  final String currencySymbol;

  /// Printed in the page footer after the company name.
  @JsonKey(name: 'footer_text')
  final String footerText;

  /// Print the company logo in the PDF header when one is uploaded.
  @JsonKey(name: 'show_logo')
  final bool showLogo;

  /// Show the unit column.
  @JsonKey(name: 'show_unit')
  final bool showUnit;

  Map<String, Object?> toJson() => _$PriceListSettingsToJson(this);
}
