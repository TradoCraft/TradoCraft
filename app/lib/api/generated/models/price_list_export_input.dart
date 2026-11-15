// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'price_list_export_input.g.dart';

@JsonSerializable()
class PriceListExportInput {
  const PriceListExportInput({
    required this.code,
    required this.name,
    this.fileName,
    this.groupIds,
    this.sortOrder,
  });
  
  factory PriceListExportInput.fromJson(Map<String, Object?> json) => _$PriceListExportInputFromJson(json);
  
  /// Unique per list, at most 32 characters.
  final String code;
  @JsonKey(includeIfNull: false,name: 'file_name')
  final String? fileName;

  /// Top-level groups of this list; empty means the whole list.
  @JsonKey(includeIfNull: false,name: 'group_ids')
  final List<String>? groupIds;
  final String name;
  @JsonKey(includeIfNull: false,name: 'sort_order')
  final int? sortOrder;

  Map<String, Object?> toJson() => _$PriceListExportInputToJson(this);
}
