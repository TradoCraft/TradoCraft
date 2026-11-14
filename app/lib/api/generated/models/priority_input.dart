// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'priority_input.g.dart';

@JsonSerializable()
class PriorityInput {
  const PriorityInput({
    required this.priority,
    required this.reason,
    this.requestId,
  });
  
  factory PriorityInput.fromJson(Map<String, Object?> json) => _$PriorityInputFromJson(json);
  
  /// low | normal | expedite
  final String priority;

  /// Why the priority changes; required.
  final String reason;

  /// The customer request this change answers; it is marked applied.
  @JsonKey(includeIfNull: false,name: 'request_id')
  final String? requestId;

  Map<String, Object?> toJson() => _$PriorityInputToJson(this);
}
