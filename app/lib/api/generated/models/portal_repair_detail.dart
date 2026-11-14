// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'portal_photo.dart';
import 'portal_repair.dart';

part 'portal_repair_detail.g.dart';

@JsonSerializable()
class PortalRepairDetail {
  const PortalRepairDetail({
    required this.photos,
    required this.repair,
  });
  
  factory PortalRepairDetail.fromJson(Map<String, Object?> json) => _$PortalRepairDetailFromJson(json);
  
  final List<PortalPhoto> photos;
  final PortalRepair repair;

  Map<String, Object?> toJson() => _$PortalRepairDetailToJson(this);
}
