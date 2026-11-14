// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'group_result.dart';
import 'issue.dart';
import 'item_table_result.dart';
import 'line.dart';
import 'value_result.dart';

part 'evaluation.g.dart';

@JsonSerializable()
class Evaluation {
  const Evaluation({
    required this.groups,
    required this.issues,
    required this.items,
    required this.lines,
    required this.project,
    required this.steps,
  });
  
  factory Evaluation.fromJson(Map<String, Object?> json) => _$EvaluationFromJson(json);
  
  final List<GroupResult> groups;
  final List<Issue> issues;
  final List<ItemTableResult> items;
  final List<Line> lines;
  final List<ValueResult> project;

  /// Formula steps used.
  final int steps;

  Map<String, Object?> toJson() => _$EvaluationToJson(this);
}
