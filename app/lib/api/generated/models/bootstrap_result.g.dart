// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bootstrap_result.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BootstrapResult _$BootstrapResultFromJson(Map<String, dynamic> json) =>
    BootstrapResult(
      admin: AdminSummary.fromJson(json['admin'] as Map<String, dynamic>),
      authMode: json['auth_mode'] as String,
      company: Company.fromJson(json['company'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$BootstrapResultToJson(BootstrapResult instance) =>
    <String, dynamic>{
      'admin': instance.admin,
      'auth_mode': instance.authMode,
      'company': instance.company,
    };
