// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'vat_check.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

VatCheck _$VatCheckFromJson(Map<String, dynamic> json) => VatCheck(
  duplicates: (json['duplicates'] as List<dynamic>)
      .map((e) => VatDuplicate.fromJson(e as Map<String, dynamic>))
      .toList(),
  status: VatStatus.fromJson(json['status'] as String),
  vatNumber: json['vat_number'] as String,
  message: json['message'] as String?,
  normalized: json['normalized'] as String?,
  vies: json['vies'] == null
      ? null
      : ViesLookup.fromJson(json['vies'] as Map<String, dynamic>),
);

Map<String, dynamic> _$VatCheckToJson(VatCheck instance) => <String, dynamic>{
  'duplicates': instance.duplicates,
  'message': ?instance.message,
  'normalized': ?instance.normalized,
  'status': instance.status,
  'vat_number': instance.vatNumber,
  'vies': ?instance.vies,
};
