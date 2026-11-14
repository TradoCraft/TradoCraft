// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'assignment_input.g.dart';

/// Where a ticket goes: both fields replace the current values (empty clears).
@JsonSerializable()
class AssignmentInput {
  const AssignmentInput({
    this.ownerUserId,
    this.teamId,
  });
  
  factory AssignmentInput.fromJson(Map<String, Object?> json) => _$AssignmentInputFromJson(json);
  
  @JsonKey(includeIfNull: false,name: 'owner_user_id')
  final String? ownerUserId;
  @JsonKey(includeIfNull: false,name: 'team_id')
  final String? teamId;

  Map<String, Object?> toJson() => _$AssignmentInputToJson(this);
}
