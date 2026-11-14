// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'bom_line_input.dart';

part 'bom_input.g.dart';

@JsonSerializable()
class BomInput {
  const BomInput({
    required this.lines,
    this.notes,
  });
  
  factory BomInput.fromJson(Map<String, Object?> json) => _$BomInputFromJson(json);
  
  final List<BomLineInput> lines;
  @JsonKey(includeIfNull: false)
  final String? notes;

  Map<String, Object?> toJson() => _$BomInputToJson(this);
}
