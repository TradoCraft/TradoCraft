// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'favorite_item.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FavoriteItem _$FavoriteItemFromJson(Map<String, dynamic> json) => FavoriteItem(
  id: json['id'] as String,
  position: (json['position'] as num).toInt(),
  productActive: json['product_active'] as bool,
  productCode: json['product_code'] as String,
  productId: json['product_id'] as String,
  productName: json['product_name'] as String,
  productionRemark: json['production_remark'] as String,
  quantity: json['quantity'] as String,
  remarks: (json['remarks'] as List<dynamic>)
      .map((e) => FavoriteRemark.fromJson(e as Map<String, dynamic>))
      .toList(),
  unit: json['unit'] as String,
  comment: json['comment'] as String?,
  parentPosition: (json['parent_position'] as num?)?.toInt(),
  percentBase: json['percent_base'] == null
      ? null
      : PercentBase.fromJson(json['percent_base'] as String),
  percentOfParent: json['percent_of_parent'] as String?,
  section: json['section'] as String?,
);

Map<String, dynamic> _$FavoriteItemToJson(FavoriteItem instance) =>
    <String, dynamic>{
      'comment': ?instance.comment,
      'id': instance.id,
      'parent_position': ?instance.parentPosition,
      'percent_base': ?instance.percentBase,
      'percent_of_parent': ?instance.percentOfParent,
      'position': instance.position,
      'product_active': instance.productActive,
      'product_code': instance.productCode,
      'product_id': instance.productId,
      'product_name': instance.productName,
      'production_remark': instance.productionRemark,
      'quantity': instance.quantity,
      'remarks': instance.remarks,
      'section': ?instance.section,
      'unit': instance.unit,
    };
