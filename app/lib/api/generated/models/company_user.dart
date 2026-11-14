// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'company_user.g.dart';

/// A colleague in the active company (for assigning tickets, owners, ...).
@JsonSerializable()
class CompanyUser {
  const CompanyUser({
    required this.displayName,
    required this.email,
    required this.id,
    required this.roles,
  });
  
  factory CompanyUser.fromJson(Map<String, Object?> json) => _$CompanyUserFromJson(json);
  
  @JsonKey(name: 'display_name')
  final String displayName;
  final String email;
  final String id;
  final List<String> roles;

  Map<String, Object?> toJson() => _$CompanyUserToJson(this);
}
