// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'escalate_input.g.dart';

@JsonSerializable()
class EscalateInput {
  const EscalateInput({
    required this.reason,
    this.raisePriority,
    this.toTeamId,
    this.toUserId,
  });
  
  factory EscalateInput.fromJson(Map<String, Object?> json) => _$EscalateInputFromJson(json);
  
  /// Raise the priority one step (low < normal < high < urgent).
  @JsonKey(includeIfNull: false,name: 'raise_priority')
  final bool? raisePriority;

  /// Why this ticket needs more attention (required).
  final String reason;

  /// Escalate to a team (its leads, else its members, are told). Not together with `to_user_id`.
  @JsonKey(includeIfNull: false,name: 'to_team_id')
  final String? toTeamId;

  /// Escalate to a person.
  @JsonKey(includeIfNull: false,name: 'to_user_id')
  final String? toUserId;

  Map<String, Object?> toJson() => _$EscalateInputToJson(this);
}
