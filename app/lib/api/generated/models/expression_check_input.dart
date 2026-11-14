// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'rule_scope.dart';

part 'expression_check_input.g.dart';

@JsonSerializable()
class ExpressionCheckInput {
  const ExpressionCheckInput({
    required this.source,
    this.definition,
    this.locals,
    this.scope,
    this.table,
    this.template,
  });
  
  factory ExpressionCheckInput.fromJson(Map<String, Object?> json) => _$ExpressionCheckInputFromJson(json);
  
  /// The definition the formula belongs to; without it names are not checked.
  @JsonKey(includeIfNull: false)
  final dynamic definition;

  /// Extra local names the formula may use (of any type), e.g. `p` in a product filter or.
  /// `each`, `each_index` and `parent` in an output rule.
  @JsonKey(includeIfNull: false)
  final List<String>? locals;

  /// The scope the formula is written in (default `project`).
  @JsonKey(includeIfNull: false)
  final RuleScope? scope;
  final String source;

  /// The item table, for item scope.
  @JsonKey(includeIfNull: false)
  final String? table;

  /// Check as a template (`text {formula} text`) instead of a formula.
  @JsonKey(includeIfNull: false)
  final bool? template;

  Map<String, Object?> toJson() => _$ExpressionCheckInputToJson(this);
}
