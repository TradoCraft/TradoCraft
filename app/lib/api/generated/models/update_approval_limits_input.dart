// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'role_limit_input.dart';

part 'update_approval_limits_input.g.dart';

/// Payload to change limits; roles that are not listed keep theirs.
@JsonSerializable()
class UpdateApprovalLimitsInput {
  const UpdateApprovalLimitsInput({
    required this.limits,
  });
  
  factory UpdateApprovalLimitsInput.fromJson(Map<String, Object?> json) => _$UpdateApprovalLimitsInputFromJson(json);
  
  final List<RoleLimitInput> limits;

  Map<String, Object?> toJson() => _$UpdateApprovalLimitsInputToJson(this);
}
