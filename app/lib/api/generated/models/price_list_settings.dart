// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'import_short_position.dart';
import 'import_title_conflict.dart';

part 'price_list_settings.g.dart';

/// Presentation of a list. No row means defaults apply to every key.
@JsonSerializable()
class PriceListSettings {
  const PriceListSettings({
    this.accentColor = '#1f4e79',
    this.currencySymbol = '',
    this.footerText = '',
    this.importGroupLevels = 2,
    this.importShortPosition = ImportShortPosition.shallowerGroup,
    this.importTitleConflict = ImportTitleConflict.lowestPosition,
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

  /// Import of the items (ADR 0100): how many leading segments of a `position` name the group.
  /// path (each the `sort_order` of a group among its siblings); the rest is the item's sort.
  /// key. 1 to 4, default 2.
  @JsonKey(name: 'import_group_levels')
  final int importGroupLevels;

  /// Import of the items: what a position with fewer segments than `import_group_levels` means.
  @JsonKey(name: 'import_short_position')
  final ImportShortPosition importShortPosition;

  /// Import of the items: which title a group gets when its rows disagree.
  @JsonKey(name: 'import_title_conflict')
  final ImportTitleConflict importTitleConflict;

  /// Print the company logo in the PDF header when one is uploaded.
  @JsonKey(name: 'show_logo')
  final bool showLogo;

  /// Show the unit column.
  @JsonKey(name: 'show_unit')
  final bool showUnit;

  Map<String, Object?> toJson() => _$PriceListSettingsToJson(this);
}
