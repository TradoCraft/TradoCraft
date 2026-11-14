// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'new_bom_input.g.dart';

@JsonSerializable()
class NewBomInput {
  const NewBomInput({
    this.copyFrom,
    this.notes,
  });
  
  factory NewBomInput.fromJson(Map<String, Object?> json) => _$NewBomInputFromJson(json);
  
  /// Copies the lines of this BOM (any revision of the same product). Default: the active BOM, if any.
  @JsonKey(includeIfNull: false,name: 'copy_from')
  final String? copyFrom;
  @JsonKey(includeIfNull: false)
  final String? notes;

  Map<String, Object?> toJson() => _$NewBomInputToJson(this);
}
