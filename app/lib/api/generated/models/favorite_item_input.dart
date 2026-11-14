// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'favorite_remark.dart';
import 'percent_base.dart';

part 'favorite_item_input.g.dart';

/// An item as sent when creating or replacing a favorite. No prices.
@JsonSerializable()
class FavoriteItemInput {
  const FavoriteItemInput({
    required this.productId,
    required this.quantity,
    this.comment,
    this.id,
    this.parentPosition,
    this.percentBase,
    this.percentOfParent,
    this.productionRemark,
    this.remarks,
    this.section,
  });

  factory FavoriteItemInput.fromJson(Map<String, Object?> json) =>
      _$FavoriteItemInputFromJson(json);

  @JsonKey(includeIfNull: false)
  final String? comment;

  /// On `PUT`: the id of an existing item of this favorite, to keep it (and the lines that point.
  /// at it). Omitted: a new item. `POST` takes no ids.
  @JsonKey(includeIfNull: false)
  final String? id;

  /// Position (1-based, in this list) of an earlier item this one belongs to. Omitted: the main.
  /// item, which must be exactly one and first.
  @JsonKey(includeIfNull: false, name: 'parent_position')
  final int? parentPosition;
  @JsonKey(includeIfNull: false, name: 'percent_base')
  final PercentBase? percentBase;
  @JsonKey(includeIfNull: false, name: 'percent_of_parent')
  final String? percentOfParent;
  @JsonKey(name: 'product_id')
  final String productId;
  @JsonKey(includeIfNull: false, name: 'production_remark')
  final String? productionRemark;
  final String quantity;

  /// Customer remarks, at most one per language; blank texts are dropped.
  @JsonKey(includeIfNull: false)
  final List<FavoriteRemark>? remarks;
  @JsonKey(includeIfNull: false)
  final String? section;

  Map<String, Object?> toJson() => _$FavoriteItemInputToJson(this);
}
