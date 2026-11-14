// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'volume_point.g.dart';

@JsonSerializable()
class VolumePoint {
  const VolumePoint({
    required this.closed,
    required this.created,
    required this.period,
  });
  
  factory VolumePoint.fromJson(Map<String, Object?> json) => _$VolumePointFromJson(json);
  
  final int closed;
  final int created;

  /// The day, or the Monday of the week.
  final DateTime period;

  Map<String, Object?> toJson() => _$VolumePointToJson(this);
}
