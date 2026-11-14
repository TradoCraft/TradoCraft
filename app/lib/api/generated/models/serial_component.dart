// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'serial_component.g.dart';

/// A serialised component in the current as-built tree, depth-first.
@JsonSerializable()
class SerialComponent {
  const SerialComponent({
    required this.addedAt,
    required this.id,
    required this.level,
    required this.parentId,
    required this.productCode,
    required this.productName,
    required this.serialNumber,
    required this.status,
  });
  
  factory SerialComponent.fromJson(Map<String, Object?> json) => _$SerialComponentFromJson(json);
  
  @JsonKey(name: 'added_at')
  final DateTime addedAt;
  final String id;
  final int level;
  @JsonKey(name: 'parent_id')
  final String parentId;
  @JsonKey(name: 'product_code')
  final String productCode;
  @JsonKey(name: 'product_name')
  final String productName;
  @JsonKey(name: 'serial_number')
  final String serialNumber;
  final String status;

  Map<String, Object?> toJson() => _$SerialComponentToJson(this);
}
