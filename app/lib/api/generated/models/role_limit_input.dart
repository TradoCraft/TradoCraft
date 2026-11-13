// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'role_limit_input.g.dart';

/// A change to one role's limit.
@JsonSerializable()
class RoleLimitInput {
  const RoleLimitInput({
    required this.role,
    this.maxAmount,
  });
  
  factory RoleLimitInput.fromJson(Map<String, Object?> json) => _$RoleLimitInputFromJson(json);
  
  /// The new limit (0 or more, at most 2 decimals); null removes it.
  @JsonKey(includeIfNull: false,name: 'max_amount')
  final String? maxAmount;
  final String role;

  Map<String, Object?> toJson() => _$RoleLimitInputToJson(this);
}
