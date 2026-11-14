// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'admin_user_update.g.dart';

@JsonSerializable()
class AdminUserUpdate {
  const AdminUserUpdate({
    required this.active,
    required this.disabledModules,
    required this.displayName,
    required this.roles,
  });
  
  factory AdminUserUpdate.fromJson(Map<String, Object?> json) => _$AdminUserUpdateFromJson(json);
  
  final bool active;
  @JsonKey(name: 'disabled_modules')
  final List<String> disabledModules;
  @JsonKey(name: 'display_name')
  final String displayName;
  final List<String> roles;

  Map<String, Object?> toJson() => _$AdminUserUpdateToJson(this);
}
