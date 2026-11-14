// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'admin_summary.g.dart';

/// The first administrator, as created.
@JsonSerializable()
class AdminSummary {
  const AdminSummary({
    required this.displayName,
    required this.email,
    required this.roles,
    required this.userId,
  });
  
  factory AdminSummary.fromJson(Map<String, Object?> json) => _$AdminSummaryFromJson(json);
  
  @JsonKey(name: 'display_name')
  final String displayName;
  final String email;
  final List<String> roles;
  @JsonKey(name: 'user_id')
  final String userId;

  Map<String, Object?> toJson() => _$AdminSummaryToJson(this);
}
