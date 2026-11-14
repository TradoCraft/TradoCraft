// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'expr_error.g.dart';

/// A syntax, type or evaluation error with its place in the formula.
@JsonSerializable()
class ExprError {
  const ExprError({
    required this.end,
    required this.message,
    required this.start,
  });
  
  factory ExprError.fromJson(Map<String, Object?> json) => _$ExprErrorFromJson(json);
  
  /// Character offset just after the problem.
  final int end;
  final String message;

  /// Character offset where the problem starts (0-based).
  final int start;

  Map<String, Object?> toJson() => _$ExprErrorToJson(this);
}
