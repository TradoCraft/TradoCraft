// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'price_list_group_input.g.dart';

@JsonSerializable()
class PriceListGroupInput {
  const PriceListGroupInput({
    required this.title,
    this.gapMm,
    this.pageBreak,
    this.parentId,
    this.showTitle,
    this.sortOrder,
  });
  
  factory PriceListGroupInput.fromJson(Map<String, Object?> json) => _$PriceListGroupInputFromJson(json);
  
  /// Millimetres of space before the group when its title is not printed, 0 to 50 (default 0).
  @JsonKey(includeIfNull: false,name: 'gap_mm')
  final String? gapMm;
  @JsonKey(includeIfNull: false,name: 'page_break')
  final bool? pageBreak;
  @JsonKey(includeIfNull: false,name: 'parent_id')
  final String? parentId;

  /// Print the title (default true). When false the title is only for the editor.
  @JsonKey(includeIfNull: false,name: 'show_title')
  final bool? showTitle;
  @JsonKey(includeIfNull: false,name: 'sort_order')
  final int? sortOrder;

  /// Title per language code (nl, fr, en, de, es); at least one.
  final Map<String, String> title;

  Map<String, Object?> toJson() => _$PriceListGroupInputToJson(this);
}
