// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'location.dart';

part 'warehouse.g.dart';

@JsonSerializable()
class Warehouse {
  const Warehouse({
    required this.active,
    required this.code,
    required this.id,
    required this.kind,
    required this.locations,
    required this.name,
    this.assignedUserId,
    this.assignedUserName,
  });
  
  factory Warehouse.fromJson(Map<String, Object?> json) => _$WarehouseFromJson(json);
  
  final bool active;

  /// The technician a service van belongs to.
  @JsonKey(includeIfNull: false,name: 'assigned_user_id')
  final String? assignedUserId;
  @JsonKey(includeIfNull: false,name: 'assigned_user_name')
  final String? assignedUserName;
  final String code;
  final String id;

  /// warehouse | van
  final String kind;
  final List<Location> locations;
  final String name;

  Map<String, Object?> toJson() => _$WarehouseToJson(this);
}
