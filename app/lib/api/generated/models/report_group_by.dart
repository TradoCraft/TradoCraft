// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'report_bucket.dart';

part 'report_group_by.g.dart';

/// A grouping, optionally bucketed by date.
@JsonSerializable()
class ReportGroupBy {
  const ReportGroupBy({
    required this.field,
    this.bucket,
  });
  
  factory ReportGroupBy.fromJson(Map<String, Object?> json) => _$ReportGroupByFromJson(json);
  
  /// For date fields: group by day, month or year.
  @JsonKey(includeIfNull: false)
  final ReportBucket? bucket;
  final String field;

  Map<String, Object?> toJson() => _$ReportGroupByToJson(this);
}
