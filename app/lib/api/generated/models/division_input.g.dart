// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'division_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DivisionInput _$DivisionInputFromJson(Map<String, dynamic> json) =>
    DivisionInput(
      code: json['code'] as String,
      name: json['name'] as String,
      active: json['active'] as bool?,
      memberUserIds: (json['member_user_ids'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      sortOrder: (json['sort_order'] as num?)?.toInt(),
    );

Map<String, dynamic> _$DivisionInputToJson(DivisionInput instance) =>
    <String, dynamic>{
      'active': ?instance.active,
      'code': instance.code,
      'member_user_ids': ?instance.memberUserIds,
      'name': instance.name,
      'sort_order': ?instance.sortOrder,
    };
