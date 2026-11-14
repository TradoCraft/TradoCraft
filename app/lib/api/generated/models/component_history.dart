// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'component_history.g.dart';

/// A component link of this unit, including removed ones.
@JsonSerializable()
class ComponentHistory {
  const ComponentHistory({
    required this.addedAt,
    required this.addedByName,
    required this.childId,
    required this.productCode,
    required this.serialNumber,
    this.removedAt,
    this.removedByName,
  });
  
  factory ComponentHistory.fromJson(Map<String, Object?> json) => _$ComponentHistoryFromJson(json);
  
  @JsonKey(name: 'added_at')
  final DateTime addedAt;
  @JsonKey(name: 'added_by_name')
  final String addedByName;
  @JsonKey(name: 'child_id')
  final String childId;
  @JsonKey(name: 'product_code')
  final String productCode;
  @JsonKey(includeIfNull: false,name: 'removed_at')
  final DateTime? removedAt;
  @JsonKey(includeIfNull: false,name: 'removed_by_name')
  final String? removedByName;
  @JsonKey(name: 'serial_number')
  final String serialNumber;

  Map<String, Object?> toJson() => _$ComponentHistoryToJson(this);
}
