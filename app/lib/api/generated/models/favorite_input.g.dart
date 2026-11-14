// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'favorite_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FavoriteInput _$FavoriteInputFromJson(Map<String, dynamic> json) =>
    FavoriteInput(
      items: (json['items'] as List<dynamic>)
          .map((e) => FavoriteItemInput.fromJson(e as Map<String, dynamic>))
          .toList(),
      name: json['name'] as String,
    );

Map<String, dynamic> _$FavoriteInputToJson(FavoriteInput instance) =>
    <String, dynamic>{'items': instance.items, 'name': instance.name};
