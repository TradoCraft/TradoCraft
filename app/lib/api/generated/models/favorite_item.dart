// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'favorite_remark.dart';
import 'percent_base.dart';

part 'favorite_item.g.dart';

/// An item of a favorite as stored.
@JsonSerializable()
class FavoriteItem {
  const FavoriteItem({
    required this.id,
    required this.position,
    required this.productActive,
    required this.productCode,
    required this.productId,
    required this.productName,
    required this.productionRemark,
    required this.quantity,
    required this.remarks,
    required this.unit,
    this.comment,
    this.parentPosition,
    this.percentBase,
    this.percentOfParent,
    this.section,
  });
  
  factory FavoriteItem.fromJson(Map<String, Object?> json) => _$FavoriteItemFromJson(json);
  
  /// The small printed comment under the line (one text, no language).
  @JsonKey(includeIfNull: false)
  final String? comment;

  /// Stable across edits that send it back; quotation lines loaded from this item point at it.
  final String id;

  /// Position of the parent item; absent for the single main item.
  @JsonKey(includeIfNull: false,name: 'parent_position')
  final int? parentPosition;
  @JsonKey(includeIfNull: false,name: 'percent_base')
  final PercentBase? percentBase;
  @JsonKey(includeIfNull: false,name: 'percent_of_parent')
  final String? percentOfParent;

  /// 1-based, in the order the lines are loaded.
  final int position;

  /// `false` when the product was deactivated after the favorite was saved: the item is kept,.
  /// the app flags it and does not load it.
  @JsonKey(name: 'product_active')
  final bool productActive;
  @JsonKey(name: 'product_code')
  final String productCode;
  @JsonKey(name: 'product_id')
  final String productId;

  /// The product's base name (the app shows the translated name when it has one).
  @JsonKey(name: 'product_name')
  final String productName;

  /// Internal remark for production (one text, no language).
  @JsonKey(name: 'production_remark')
  final String productionRemark;

  /// Main item: the default quantity. Other items: the quantity per ONE unit of the main item.
  final String quantity;

  /// The customer remark per language, in the order nl, fr, en, de, es.
  final List<FavoriteRemark> remarks;
  @JsonKey(includeIfNull: false)
  final String? section;
  final String unit;

  Map<String, Object?> toJson() => _$FavoriteItemToJson(this);
}
