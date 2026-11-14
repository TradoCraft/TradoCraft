// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'pin.dart';

part 'inputs.g.dart';

/// What the user entered. Unknown names are ignored.
@JsonSerializable()
class Inputs {
  const Inputs({
    this.groups,
    this.items,
    this.pins,
    this.project,
  });
  
  factory Inputs.fromJson(Map<String, Object?> json) => _$InputsFromJson(json);
  
  /// Group field values by group name, then field name.
  @JsonKey(includeIfNull: false)
  final dynamic groups;

  /// Rows per item table: field values by name.
  @JsonKey(includeIfNull: false)
  final dynamic items;
  @JsonKey(includeIfNull: false)
  final List<Pin>? pins;

  /// Project field values by name.
  @JsonKey(includeIfNull: false)
  final dynamic project;

  Map<String, Object?> toJson() => _$InputsToJson(this);
}
