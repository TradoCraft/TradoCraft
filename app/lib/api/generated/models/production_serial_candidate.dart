// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'production_serial_candidate.g.dart';

@JsonSerializable()
class ProductionSerialCandidate {
  const ProductionSerialCandidate({
    required this.id,
    required this.location,
    required this.locationId,
    required this.serialNumber,
  });
  
  factory ProductionSerialCandidate.fromJson(Map<String, Object?> json) => _$ProductionSerialCandidateFromJson(json);
  
  final String id;
  final String location;
  @JsonKey(name: 'location_id')
  final String locationId;
  @JsonKey(name: 'serial_number')
  final String serialNumber;

  Map<String, Object?> toJson() => _$ProductionSerialCandidateToJson(this);
}
