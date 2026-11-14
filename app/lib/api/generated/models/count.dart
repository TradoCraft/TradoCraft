// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'count.g.dart';

@JsonSerializable()
class Count {
  const Count({
    required this.countedCount,
    required this.createdAt,
    required this.createdByName,
    required this.id,
    required this.lineCount,
    required this.note,
    required this.number,
    required this.status,
    required this.warehouseCode,
    required this.warehouseId,
    this.closedAt,
    this.locationCode,
    this.locationId,
    this.productId,
  });
  
  factory Count.fromJson(Map<String, Object?> json) => _$CountFromJson(json);
  
  @JsonKey(includeIfNull: false,name: 'closed_at')
  final DateTime? closedAt;

  /// Lines with a counted quantity.
  @JsonKey(name: 'counted_count')
  final int countedCount;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @JsonKey(name: 'created_by_name')
  final String createdByName;
  final String id;
  @JsonKey(name: 'line_count')
  final int lineCount;
  @JsonKey(includeIfNull: false,name: 'location_code')
  final String? locationCode;
  @JsonKey(includeIfNull: false,name: 'location_id')
  final String? locationId;
  final String note;
  final String number;
  @JsonKey(includeIfNull: false,name: 'product_id')
  final String? productId;

  /// counting | posted | cancelled
  final String status;
  @JsonKey(name: 'warehouse_code')
  final String warehouseCode;
  @JsonKey(name: 'warehouse_id')
  final String warehouseId;

  Map<String, Object?> toJson() => _$CountToJson(this);
}
