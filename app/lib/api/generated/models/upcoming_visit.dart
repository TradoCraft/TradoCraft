// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'upcoming_visit.g.dart';

@JsonSerializable()
class UpcomingVisit {
  const UpcomingVisit({
    required this.dueDate,
    required this.generateOn,
    required this.kind,
    required this.templateId,
    required this.title,
    this.jobId,
    this.jobNumber,
  });
  
  factory UpcomingVisit.fromJson(Map<String, Object?> json) => _$UpcomingVisitFromJson(json);
  
  @JsonKey(name: 'due_date')
  final DateTime dueDate;

  /// The day the job is (or was) generated.
  @JsonKey(name: 'generate_on')
  final DateTime generateOn;

  /// The job, once generated.
  @JsonKey(includeIfNull: false,name: 'job_id')
  final String? jobId;
  @JsonKey(includeIfNull: false,name: 'job_number')
  final String? jobNumber;
  final String kind;
  @JsonKey(name: 'template_id')
  final String templateId;
  final String title;

  Map<String, Object?> toJson() => _$UpcomingVisitToJson(this);
}
