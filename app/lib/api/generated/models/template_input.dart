// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'template_input.g.dart';

@JsonSerializable()
class TemplateInput {
  const TemplateInput({
    required this.recurrence,
    required this.title,
    this.active,
    this.anchorDate,
    this.estimatedMinutes,
    this.id,
    this.instructions,
    this.intervalN,
    this.kind,
    this.leadDays,
    this.months,
    this.tasks,
    this.technicianIds,
  });
  
  factory TemplateInput.fromJson(Map<String, Object?> json) => _$TemplateInputFromJson(json);
  
  @JsonKey(includeIfNull: false)
  final bool? active;

  /// The first due date; defaults to the start of the contract.
  @JsonKey(includeIfNull: false,name: 'anchor_date')
  final DateTime? anchorDate;
  @JsonKey(includeIfNull: false,name: 'estimated_minutes')
  final int? estimatedMinutes;

  /// Give the id of an existing template to change it; without one a new template is made.
  @JsonKey(includeIfNull: false)
  final String? id;
  @JsonKey(includeIfNull: false)
  final String? instructions;
  @JsonKey(includeIfNull: false,name: 'interval_n')
  final int? intervalN;
  @JsonKey(includeIfNull: false)
  final String? kind;
  @JsonKey(includeIfNull: false,name: 'lead_days')
  final int? leadDays;
  @JsonKey(includeIfNull: false)
  final List<int>? months;
  final String recurrence;
  @JsonKey(includeIfNull: false)
  final List<String>? tasks;
  @JsonKey(includeIfNull: false,name: 'technician_ids')
  final List<String>? technicianIds;
  final String title;

  Map<String, Object?> toJson() => _$TemplateInputToJson(this);
}
