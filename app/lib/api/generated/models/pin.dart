// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'pin.g.dart';

/// A user's own value for an overridable computed value.
@JsonSerializable()
class Pin {
  const Pin({
    required this.name,
    required this.value,
    this.calculated,
    this.group,
    this.row,
    this.table,
  });
  
  factory Pin.fromJson(Map<String, Object?> json) => _$PinFromJson(json);
  
  /// The calculated value when the pin was made; when the calculation now differs the pin is.
  /// reported as stale.
  @JsonKey(includeIfNull: false)
  final dynamic calculated;

  /// For a group value: the group name.
  @JsonKey(includeIfNull: false)
  final String? group;

  /// The computed value's name.
  final String name;

  /// ... and the row (0-based).
  @JsonKey(includeIfNull: false)
  final int? row;

  /// For an item value: the item table ...
  @JsonKey(includeIfNull: false)
  final String? table;
  final dynamic value;

  Map<String, Object?> toJson() => _$PinToJson(this);
}
