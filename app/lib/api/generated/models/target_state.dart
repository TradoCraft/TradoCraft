// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'target_state.g.dart';

/// What one target (first response or resolution) looks like at `now`.
@JsonSerializable()
class TargetState {
  const TargetState({
    required this.atRisk,
    required this.breached,
    this.dueAt,
    this.metAt,
    this.minutesRemaining,
  });
  
  factory TargetState.fromJson(Map<String, Object?> json) => _$TargetStateFromJson(json);
  
  /// Not breached, not met yet and less than 25 % of the window is left.
  @JsonKey(name: 'at_risk')
  final bool atRisk;

  /// The due time passed before it was met (or, if still open, it has passed).
  final bool breached;

  /// When it is due; empty when the ticket has no service level (internal tickets).
  @JsonKey(includeIfNull: false,name: 'due_at')
  final DateTime? dueAt;

  /// When it was met (first response sent, ticket closed).
  @JsonKey(includeIfNull: false,name: 'met_at')
  final DateTime? metAt;

  /// Whole minutes left (negative when overdue). Empty once the target is met.
  @JsonKey(includeIfNull: false,name: 'minutes_remaining')
  final int? minutesRemaining;

  Map<String, Object?> toJson() => _$TargetStateToJson(this);
}
