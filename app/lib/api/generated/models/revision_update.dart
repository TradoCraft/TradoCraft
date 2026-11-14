// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'revision_update.g.dart';

@JsonSerializable()
class RevisionUpdate {
  const RevisionUpdate({
    required this.definition,
    this.notes,
  });
  
  factory RevisionUpdate.fromJson(Map<String, Object?> json) => _$RevisionUpdateFromJson(json);
  
  final dynamic definition;
  @JsonKey(includeIfNull: false)
  final String? notes;

  Map<String, Object?> toJson() => _$RevisionUpdateToJson(this);
}
