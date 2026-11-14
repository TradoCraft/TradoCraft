// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'status_counts.g.dart';

@JsonSerializable()
class StatusCounts {
  const StatusCounts({
    required this.suitable,
    required this.unknown,
    required this.unsuitable,
  });
  
  factory StatusCounts.fromJson(Map<String, Object?> json) => _$StatusCountsFromJson(json);
  
  final int suitable;
  final int unknown;
  final int unsuitable;

  Map<String, Object?> toJson() => _$StatusCountsToJson(this);
}
