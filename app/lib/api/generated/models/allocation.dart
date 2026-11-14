// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'allocation.g.dart';

@JsonSerializable()
class Allocation {
  const Allocation({
    required this.createdAt,
    required this.id,
    required this.location,
    required this.locationId,
    required this.quantity,
    this.lotId,
    this.lotNumber,
  });
  
  factory Allocation.fromJson(Map<String, Object?> json) => _$AllocationFromJson(json);
  
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  final String id;
  final String location;
  @JsonKey(name: 'location_id')
  final String locationId;
  @JsonKey(includeIfNull: false,name: 'lot_id')
  final String? lotId;
  @JsonKey(includeIfNull: false,name: 'lot_number')
  final String? lotNumber;
  final String quantity;

  Map<String, Object?> toJson() => _$AllocationToJson(this);
}
