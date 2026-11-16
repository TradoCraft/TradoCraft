// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'price_list_export.g.dart';

/// Which groups go into one file. One group is an individual chapter (or section), several a.
/// combination; each is printed with everything below it.
@JsonSerializable()
class PriceListExport {
  const PriceListExport({
    required this.code,
    required this.groupIds,
    required this.id,
    required this.name,
    required this.sortOrder,
    this.fileName,
  });
  
  factory PriceListExport.fromJson(Map<String, Object?> json) => _$PriceListExportFromJson(json);
  
  final String code;

  /// Optional file name template (placeholders `{list}`, `{zone}`, `{lang}`, `{name}`,.
  /// `{code}`); the name is used when absent.
  @JsonKey(includeIfNull: false,name: 'file_name')
  final String? fileName;

  /// Groups of the list, of any depth; empty means the whole list.
  @JsonKey(name: 'group_ids')
  final List<String> groupIds;
  final String id;
  final String name;
  @JsonKey(name: 'sort_order')
  final int sortOrder;

  Map<String, Object?> toJson() => _$PriceListExportToJson(this);
}
