// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'admin_user.g.dart';

/// A member of the active company, including deactivated ones.
@JsonSerializable()
class AdminUser {
  const AdminUser({
    required this.active,
    required this.disabledModules,
    required this.displayName,
    required this.email,
    required this.hasSignedIn,
    required this.roles,
    required this.userId,
  });
  
  factory AdminUser.fromJson(Map<String, Object?> json) => _$AdminUserFromJson(json);
  
  /// False when the membership in this company is deactivated.
  final bool active;

  /// Modules switched off for this user (on top of the company's).
  @JsonKey(name: 'disabled_modules')
  final List<String> disabledModules;
  @JsonKey(name: 'display_name')
  final String displayName;
  final String email;

  /// Whether the person has signed in with the identity provider yet.
  @JsonKey(name: 'has_signed_in')
  final bool hasSignedIn;
  final List<String> roles;
  @JsonKey(name: 'user_id')
  final String userId;

  Map<String, Object?> toJson() => _$AdminUserToJson(this);
}
