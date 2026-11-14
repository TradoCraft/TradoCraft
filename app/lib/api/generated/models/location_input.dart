// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'location_input.g.dart';

@JsonSerializable()
class LocationInput {
  const LocationInput({
    required this.code,
    this.active,
    this.name,
    this.warehouseId,
  });
  
  factory LocationInput.fromJson(Map<String, Object?> json) => _$LocationInputFromJson(json);
  
  @JsonKey(includeIfNull: false)
  final bool? active;
  final String code;
  @JsonKey(includeIfNull: false)
  final String? name;

  /// Required when creating.
  @JsonKey(includeIfNull: false,name: 'warehouse_id')
  final String? warehouseId;

  Map<String, Object?> toJson() => _$LocationInputToJson(this);
}
