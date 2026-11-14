// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'baseline_item_type_update.g.dart';

/// Everything but the code, which cannot change.
@JsonSerializable()
class BaselineItemTypeUpdate {
  const BaselineItemTypeUpdate({
    required this.name,
    this.active,
    this.allowTopLevel,
    this.allowedParentCodes,
    this.sortOrder,
  });
  
  factory BaselineItemTypeUpdate.fromJson(Map<String, Object?> json) => _$BaselineItemTypeUpdateFromJson(json);
  
  @JsonKey(includeIfNull: false)
  final bool? active;
  @JsonKey(includeIfNull: false,name: 'allow_top_level')
  final bool? allowTopLevel;
  @JsonKey(includeIfNull: false,name: 'allowed_parent_codes')
  final List<String>? allowedParentCodes;
  final String name;
  @JsonKey(includeIfNull: false,name: 'sort_order')
  final int? sortOrder;

  Map<String, Object?> toJson() => _$BaselineItemTypeUpdateToJson(this);
}
