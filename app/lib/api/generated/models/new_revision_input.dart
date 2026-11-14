// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'new_revision_input.g.dart';

@JsonSerializable()
class NewRevisionInput {
  const NewRevisionInput({
    this.copyFrom,
    this.notes,
  });
  
  factory NewRevisionInput.fromJson(Map<String, Object?> json) => _$NewRevisionInputFromJson(json);
  
  /// A revision of the same model to copy; the active one when left out.
  @JsonKey(includeIfNull: false,name: 'copy_from')
  final String? copyFrom;
  @JsonKey(includeIfNull: false)
  final String? notes;

  Map<String, Object?> toJson() => _$NewRevisionInputToJson(this);
}
