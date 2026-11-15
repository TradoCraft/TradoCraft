// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'price_list_group.g.dart';

@JsonSerializable()
class PriceListGroup {
  const PriceListGroup({
    required this.gapMm,
    required this.id,
    required this.pageBreak,
    required this.showTitle,
    required this.sortOrder,
    required this.title,
    this.parentId,
  });
  
  factory PriceListGroup.fromJson(Map<String, Object?> json) => _$PriceListGroupFromJson(json);
  
  /// Millimetres of space before an untitled group (0 to 50), always two decimals.
  @JsonKey(name: 'gap_mm')
  final String gapMm;
  final String id;

  /// Start a new page before this group (top-level groups only).
  @JsonKey(name: 'page_break')
  final bool pageBreak;
  @JsonKey(includeIfNull: false,name: 'parent_id')
  final String? parentId;

  /// False: the title is kept for the editor but never printed.
  @JsonKey(name: 'show_title')
  final bool showTitle;
  @JsonKey(name: 'sort_order')
  final int sortOrder;

  /// Title per language code.
  final Map<String, String> title;

  Map<String, Object?> toJson() => _$PriceListGroupToJson(this);
}
