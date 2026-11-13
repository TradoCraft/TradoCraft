// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'approval_limits.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ApprovalLimits _$ApprovalLimitsFromJson(Map<String, dynamic> json) =>
    ApprovalLimits(
      currency: json['currency'] as String,
      roles: (json['roles'] as List<dynamic>)
          .map((e) => RoleLimit.fromJson(e as Map<String, dynamic>))
          .toList(),
      yourLimit: json['your_limit'] as String?,
    );

Map<String, dynamic> _$ApprovalLimitsToJson(ApprovalLimits instance) =>
    <String, dynamic>{
      'currency': instance.currency,
      'roles': instance.roles,
      'your_limit': ?instance.yourLimit,
    };
