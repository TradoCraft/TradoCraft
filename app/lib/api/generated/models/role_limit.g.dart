// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'role_limit.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RoleLimit _$RoleLimitFromJson(Map<String, dynamic> json) => RoleLimit(
  role: json['role'] as String,
  maxAmount: json['max_amount'] as String?,
);

Map<String, dynamic> _$RoleLimitToJson(RoleLimit instance) => <String, dynamic>{
  'max_amount': ?instance.maxAmount,
  'role': instance.role,
};
