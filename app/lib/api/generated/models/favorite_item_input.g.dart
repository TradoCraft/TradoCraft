// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'favorite_item_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FavoriteItemInput _$FavoriteItemInputFromJson(Map<String, dynamic> json) =>
    FavoriteItemInput(
      productId: json['product_id'] as String,
      quantity: json['quantity'] as String,
      comment: json['comment'] as String?,
      id: json['id'] as String?,
      parentPosition: (json['parent_position'] as num?)?.toInt(),
      percentBase: json['percent_base'] == null
          ? null
          : PercentBase.fromJson(json['percent_base'] as String),
      percentOfParent: json['percent_of_parent'] as String?,
      productionRemark: json['production_remark'] as String?,
      remarks: (json['remarks'] as List<dynamic>?)
          ?.map((e) => FavoriteRemark.fromJson(e as Map<String, dynamic>))
          .toList(),
      section: json['section'] as String?,
    );

Map<String, dynamic> _$FavoriteItemInputToJson(FavoriteItemInput instance) =>
    <String, dynamic>{
      'comment': ?instance.comment,
      'id': ?instance.id,
      'parent_position': ?instance.parentPosition,
      'percent_base': ?instance.percentBase,
      'percent_of_parent': ?instance.percentOfParent,
      'product_id': instance.productId,
      'production_remark': ?instance.productionRemark,
      'quantity': instance.quantity,
      'remarks': ?instance.remarks,
      'section': ?instance.section,
    };
