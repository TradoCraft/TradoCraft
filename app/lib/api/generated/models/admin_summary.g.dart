// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'admin_summary.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AdminSummary _$AdminSummaryFromJson(Map<String, dynamic> json) => AdminSummary(
  displayName: json['display_name'] as String,
  email: json['email'] as String,
  roles: (json['roles'] as List<dynamic>).map((e) => e as String).toList(),
  userId: json['user_id'] as String,
);

Map<String, dynamic> _$AdminSummaryToJson(AdminSummary instance) =>
    <String, dynamic>{
      'display_name': instance.displayName,
      'email': instance.email,
      'roles': instance.roles,
      'user_id': instance.userId,
    };
