// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'bom_line.dart';

part 'bom.g.dart';

@JsonSerializable()
class Bom {
  const Bom({
    required this.createdAt,
    required this.id,
    required this.lines,
    required this.notes,
    required this.productCode,
    required this.productId,
    required this.productName,
    required this.revision,
    required this.status,
    this.activatedAt,
  });
  
  factory Bom.fromJson(Map<String, Object?> json) => _$BomFromJson(json);
  
  @JsonKey(includeIfNull: false,name: 'activated_at')
  final DateTime? activatedAt;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  final String id;
  final List<BomLine> lines;
  final String notes;
  @JsonKey(name: 'product_code')
  final String productCode;
  @JsonKey(name: 'product_id')
  final String productId;
  @JsonKey(name: 'product_name')
  final String productName;
  final int revision;

  /// draft | active | obsolete
  final String status;

  Map<String, Object?> toJson() => _$BomToJson(this);
}
