// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'role_info.g.dart';

/// A role and the permissions it grants (before modules are applied).
@JsonSerializable()
class RoleInfo {
  const RoleInfo({
    required this.permissions,
    required this.role,
  });
  
  factory RoleInfo.fromJson(Map<String, Object?> json) => _$RoleInfoFromJson(json);
  
  /// Sorted permission codes, e.g. `quotations.write`.
  final List<String> permissions;
  final String role;

  Map<String, Object?> toJson() => _$RoleInfoToJson(this);
}
