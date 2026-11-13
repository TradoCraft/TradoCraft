// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'role_limit_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RoleLimitInput _$RoleLimitInputFromJson(Map<String, dynamic> json) =>
    RoleLimitInput(
      role: json['role'] as String,
      maxAmount: json['max_amount'] as String?,
    );

Map<String, dynamic> _$RoleLimitInputToJson(RoleLimitInput instance) =>
    <String, dynamic>{'max_amount': ?instance.maxAmount, 'role': instance.role};
