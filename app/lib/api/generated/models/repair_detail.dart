// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'photo.dart';
import 'repair.dart';
import 'repair_event.dart';

part 'repair_detail.g.dart';

@JsonSerializable()
class RepairDetail {
  const RepairDetail({
    required this.events,
    required this.photos,
    required this.repair,
  });
  
  factory RepairDetail.fromJson(Map<String, Object?> json) => _$RepairDetailFromJson(json);
  
  final List<RepairEvent> events;
  final List<Photo> photos;
  final Repair repair;

  Map<String, Object?> toJson() => _$RepairDetailToJson(this);
}
