// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'role_limit.g.dart';

/// The limit of one role; `None` means no limit.
@JsonSerializable()
class RoleLimit {
  const RoleLimit({
    required this.role,
    this.maxAmount,
  });
  
  factory RoleLimit.fromJson(Map<String, Object?> json) => _$RoleLimitFromJson(json);
  
  @JsonKey(includeIfNull: false,name: 'max_amount')
  final String? maxAmount;
  final String role;

  Map<String, Object?> toJson() => _$RoleLimitToJson(this);
}
