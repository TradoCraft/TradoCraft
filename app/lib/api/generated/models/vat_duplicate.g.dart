// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'vat_duplicate.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

VatDuplicate _$VatDuplicateFromJson(Map<String, dynamic> json) => VatDuplicate(
  active: json['active'] as bool,
  code: json['code'] as String,
  id: json['id'] as String,
  name: json['name'] as String,
);

Map<String, dynamic> _$VatDuplicateToJson(VatDuplicate instance) =>
    <String, dynamic>{
      'active': instance.active,
      'code': instance.code,
      'id': instance.id,
      'name': instance.name,
    };
