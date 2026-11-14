// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'expr_error.dart';

part 'expression_check_result.g.dart';

@JsonSerializable()
class ExpressionCheckResult {
  const ExpressionCheckResult({
    required this.errors,
    required this.ok,
    required this.type,
  });
  
  factory ExpressionCheckResult.fromJson(Map<String, Object?> json) => _$ExpressionCheckResultFromJson(json);
  
  final List<ExprError> errors;
  final bool ok;

  /// The inferred type, e.g. `decimal`, `list of text`, `any`.
  final String type;

  Map<String, Object?> toJson() => _$ExpressionCheckResultToJson(this);
}
