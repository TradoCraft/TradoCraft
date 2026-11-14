// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'product_match.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ProductMatch _$ProductMatchFromJson(Map<String, dynamic> json) => ProductMatch(
  code: json['code'] as String,
  id: json['id'] as String,
  name: json['name'] as String,
  reasons: (json['reasons'] as List<dynamic>)
      .map((e) => Reason.fromJson(e as Map<String, dynamic>))
      .toList(),
  status: MatchStatus.fromJson(json['status'] as String),
  familyCode: json['family_code'] as String?,
  familyId: json['family_id'] as String?,
);

Map<String, dynamic> _$ProductMatchToJson(ProductMatch instance) =>
    <String, dynamic>{
      'code': instance.code,
      'family_code': ?instance.familyCode,
      'family_id': ?instance.familyId,
      'id': instance.id,
      'name': instance.name,
      'reasons': instance.reasons,
      'status': instance.status,
    };
