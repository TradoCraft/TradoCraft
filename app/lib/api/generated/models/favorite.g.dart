// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'favorite.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Favorite _$FavoriteFromJson(Map<String, dynamic> json) => Favorite(
  createdAt: DateTime.parse(json['created_at'] as String),
  createdBy: json['created_by'] as String,
  id: json['id'] as String,
  items: (json['items'] as List<dynamic>)
      .map((e) => FavoriteItem.fromJson(e as Map<String, dynamic>))
      .toList(),
  name: json['name'] as String,
  updatedAt: DateTime.parse(json['updated_at'] as String),
);

Map<String, dynamic> _$FavoriteToJson(Favorite instance) => <String, dynamic>{
  'created_at': instance.createdAt.toIso8601String(),
  'created_by': instance.createdBy,
  'id': instance.id,
  'items': instance.items,
  'name': instance.name,
  'updated_at': instance.updatedAt.toIso8601String(),
};
