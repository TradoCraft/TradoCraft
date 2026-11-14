// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'admin_user_create.g.dart';

@JsonSerializable()
class AdminUserCreate {
  const AdminUserCreate({
    required this.displayName,
    required this.email,
    required this.roles,
    this.disabledModules,
  });
  
  factory AdminUserCreate.fromJson(Map<String, Object?> json) => _$AdminUserCreateFromJson(json);
  
  @JsonKey(includeIfNull: false,name: 'disabled_modules')
  final List<String>? disabledModules;
  @JsonKey(name: 'display_name')
  final String displayName;
  final String email;
  final List<String> roles;

  Map<String, Object?> toJson() => _$AdminUserCreateToJson(this);
}
