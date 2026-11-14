// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'favorite_remark_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FavoriteRemarkInput _$FavoriteRemarkInputFromJson(Map<String, dynamic> json) =>
    FavoriteRemarkInput(
      text: json['text'] as String,
      overwrite: json['overwrite'] as bool?,
    );

Map<String, dynamic> _$FavoriteRemarkInputToJson(
  FavoriteRemarkInput instance,
) => <String, dynamic>{'overwrite': ?instance.overwrite, 'text': instance.text};
