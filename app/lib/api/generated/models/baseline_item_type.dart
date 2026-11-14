// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'baseline_item_type.g.dart';

@JsonSerializable()
class BaselineItemType {
  const BaselineItemType({
    required this.active,
    required this.allowTopLevel,
    required this.allowedParentCodes,
    required this.code,
    required this.id,
    required this.name,
    required this.sortOrder,
  });
  
  factory BaselineItemType.fromJson(Map<String, Object?> json) => _$BaselineItemTypeFromJson(json);
  
  /// Inactive types take no new items; existing items stay.
  final bool active;

  /// Whether an item of this type may stand at the top level of the baseline.
  @JsonKey(name: 'allow_top_level')
  final bool allowTopLevel;

  /// Type codes an item of this type may be nested under.
  @JsonKey(name: 'allowed_parent_codes')
  final List<String> allowedParentCodes;

  /// snake_case; the scope of this type's attribute definitions. Fixed once created.
  final String code;
  final String id;
  final String name;
  @JsonKey(name: 'sort_order')
  final int sortOrder;

  Map<String, Object?> toJson() => _$BaselineItemTypeToJson(this);
}
