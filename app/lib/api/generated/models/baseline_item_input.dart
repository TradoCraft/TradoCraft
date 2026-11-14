// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'baseline_item_input.g.dart';

@JsonSerializable()
class BaselineItemInput {
  const BaselineItemInput({
    required this.typeCode,
    this.name,
    this.parentId,
    this.quantity,
    this.sortOrder,
    this.values,
  });
  
  factory BaselineItemInput.fromJson(Map<String, Object?> json) => _$BaselineItemInputFromJson(json);
  
  /// Optional, e.g. the name of a bell.
  @JsonKey(includeIfNull: false)
  final String? name;

  /// An item of the same opportunity; omit for the top level.
  @JsonKey(includeIfNull: false,name: 'parent_id')
  final String? parentId;

  /// At least 1.
  @JsonKey(includeIfNull: false)
  final int? quantity;
  @JsonKey(includeIfNull: false,name: 'sort_order')
  final int? sortOrder;

  /// Code of a baseline item type of the company (it must be active).
  @JsonKey(name: 'type_code')
  final String typeCode;

  /// Attribute values keyed by definition key; see the definitions of the item's type.
  @JsonKey(includeIfNull: false)
  final dynamic values;

  Map<String, Object?> toJson() => _$BaselineItemInputToJson(this);
}
