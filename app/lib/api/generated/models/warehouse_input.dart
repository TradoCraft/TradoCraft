// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'warehouse_input.g.dart';

@JsonSerializable()
class WarehouseInput {
  const WarehouseInput({
    required this.code,
    required this.name,
    this.active,
    this.assignedUserId,
    this.kind,
  });
  
  factory WarehouseInput.fromJson(Map<String, Object?> json) => _$WarehouseInputFromJson(json);
  
  @JsonKey(includeIfNull: false)
  final bool? active;
  @JsonKey(includeIfNull: false,name: 'assigned_user_id')
  final String? assignedUserId;
  final String code;

  /// warehouse | van. Cannot be changed afterwards.
  @JsonKey(includeIfNull: false)
  final String? kind;
  final String name;

  Map<String, Object?> toJson() => _$WarehouseInputToJson(this);
}
