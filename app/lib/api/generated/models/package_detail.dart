// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'package.dart';
import 'package_event.dart';
import 'package_repair_ref.dart';
import 'photo.dart';

part 'package_detail.g.dart';

@JsonSerializable()
class PackageDetail {
  const PackageDetail({
    required this.events,
    required this.package,
    required this.photos,
    required this.repairs,
  });
  
  factory PackageDetail.fromJson(Map<String, Object?> json) => _$PackageDetailFromJson(json);
  
  final List<PackageEvent> events;
  final Package package;

  /// Photos of the box and its condition. Fetch one from `/packages/{id}/photos/{photo_id}`.
  final List<Photo> photos;
  final List<PackageRepairRef> repairs;

  Map<String, Object?> toJson() => _$PackageDetailToJson(this);
}
