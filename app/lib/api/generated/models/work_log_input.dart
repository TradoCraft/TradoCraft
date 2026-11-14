// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'work_log_input.g.dart';

@JsonSerializable()
class WorkLogInput {
  const WorkLogInput({
    required this.endedAt,
    required this.startedAt,
    this.id,
    this.kind,
    this.notes,
  });
  
  factory WorkLogInput.fromJson(Map<String, Object?> json) => _$WorkLogInputFromJson(json);
  
  @JsonKey(name: 'ended_at')
  final DateTime endedAt;

  /// Chosen by the client: sending the same id again changes nothing (offline retries).
  @JsonKey(includeIfNull: false)
  final String? id;

  /// work | travel
  @JsonKey(includeIfNull: false)
  final String? kind;
  @JsonKey(includeIfNull: false)
  final String? notes;
  @JsonKey(name: 'started_at')
  final DateTime startedAt;

  Map<String, Object?> toJson() => _$WorkLogInputToJson(this);
}
