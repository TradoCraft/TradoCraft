// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'issue_severity.dart';

part 'issue.g.dart';

@JsonSerializable()
class Issue {
  const Issue({
    required this.code,
    required this.message,
    required this.scope,
    required this.severity,
    this.field,
    this.rule,
  });
  
  factory Issue.fromJson(Map<String, Object?> json) => _$IssueFromJson(json);
  
  /// The validation id, or a built-in code: required, out_of_range, invalid_value,.
  /// evaluation_error, pin_stale, pin_ignored, rows, no_code, unknown_product.
  final String code;
  @JsonKey(includeIfNull: false)
  final String? field;
  final String message;
  @JsonKey(includeIfNull: false)
  final String? rule;
  final String scope;
  final IssueSeverity severity;

  Map<String, Object?> toJson() => _$IssueToJson(this);
}
