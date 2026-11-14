// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'technician.dart';

part 'visit_template.g.dart';

@JsonSerializable()
class VisitTemplate {
  const VisitTemplate({
    required this.active,
    required this.anchorDate,
    required this.id,
    required this.instructions,
    required this.intervalN,
    required this.kind,
    required this.leadDays,
    required this.months,
    required this.position,
    required this.recurrence,
    required this.tasks,
    required this.technicians,
    required this.title,
    this.estimatedMinutes,
    this.nextDue,
  });
  
  factory VisitTemplate.fromJson(Map<String, Object?> json) => _$VisitTemplateFromJson(json);
  
  final bool active;

  /// The first due date (and the day of the month for `months_list`).
  @JsonKey(name: 'anchor_date')
  final DateTime anchorDate;
  @JsonKey(includeIfNull: false,name: 'estimated_minutes')
  final int? estimatedMinutes;
  final String id;
  final String instructions;

  /// Every N weeks or months.
  @JsonKey(name: 'interval_n')
  final int intervalN;
  final String kind;

  /// The job is generated this many days before the due date.
  @JsonKey(name: 'lead_days')
  final int leadDays;

  /// The months (1-12) of a `months_list` recurrence.
  final List<int> months;

  /// The next due date from today on, within the contract's term.
  @JsonKey(includeIfNull: false,name: 'next_due')
  final DateTime? nextDue;
  final int position;

  /// weeks | months | months_list
  final String recurrence;
  final List<String> tasks;
  final List<Technician> technicians;
  final String title;

  Map<String, Object?> toJson() => _$VisitTemplateToJson(this);
}
