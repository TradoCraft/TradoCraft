// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'rule_outcome.dart';

part 'dry_run.g.dart';

@JsonSerializable()
class DryRun {
  const DryRun({
    required this.rules,
    required this.ticketNumber,
    required this.trigger,
  });
  
  factory DryRun.fromJson(Map<String, Object?> json) => _$DryRunFromJson(json);
  
  /// One entry per rule, in running order. Nothing was changed.
  final List<RuleOutcome> rules;
  @JsonKey(name: 'ticket_number')
  final String ticketNumber;
  final String trigger;

  Map<String, Object?> toJson() => _$DryRunToJson(this);
}
