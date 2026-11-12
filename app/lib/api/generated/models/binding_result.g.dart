// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'binding_result.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BindingResult _$BindingResultFromJson(Map<String, dynamic> json) =>
    BindingResult(
      outcome: json['outcome'] as String,
      reason: json['reason'] as String?,
      userEmail: json['user_email'] as String?,
      userId: json['user_id'] as String?,
    );

Map<String, dynamic> _$BindingResultToJson(BindingResult instance) =>
    <String, dynamic>{
      'outcome': instance.outcome,
      'reason': ?instance.reason,
      'user_email': ?instance.userEmail,
      'user_id': ?instance.userId,
    };
