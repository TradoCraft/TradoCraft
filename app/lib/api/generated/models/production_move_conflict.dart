// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'production_move_conflict.g.dart';

/// One problem with a move.
@JsonSerializable()
class ProductionMoveConflict {
  const ProductionMoveConflict({
    required this.kind,
    required this.messageKey,
    required this.severity,
    this.day,
  });
  
  factory ProductionMoveConflict.fromJson(Map<String, Object?> json) => _$ProductionMoveConflictFromJson(json);
  
  /// The day concerned, when there is one.
  @JsonKey(includeIfNull: false)
  final DateTime? day;

  /// `inactive_work_centre`, `operation_started`, `on_closure`, `overload`, `before_predecessor`,.
  /// `after_successor` or `later_than_ready`.
  final String kind;

  /// The key the app translates, `production.conflict.<kind>`.
  @JsonKey(name: 'message_key')
  final String messageKey;

  /// `error` or `warning`.
  final String severity;

  Map<String, Object?> toJson() => _$ProductionMoveConflictToJson(this);
}
