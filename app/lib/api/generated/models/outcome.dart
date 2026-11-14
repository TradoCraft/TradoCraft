// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'change.dart';

part 'outcome.g.dart';

/// What happened to one rule in one evaluation.
@JsonSerializable()
class Outcome {
  const Outcome({
    required this.changes,
    required this.result,
    required this.ruleId,
    required this.ruleName,
  });

  factory Outcome.fromJson(Map<String, Object?> json) =>
      _$OutcomeFromJson(json);

  /// The changes that actually change the ticket (actions that change nothing are left out).
  final List<Change> changes;

  /// matched | no_match | inactive | other_trigger | after_stop
  final String result;
  @JsonKey(name: 'rule_id')
  final String ruleId;
  @JsonKey(name: 'rule_name')
  final String ruleName;

  Map<String, Object?> toJson() => _$OutcomeToJson(this);
}
