// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'column_pair.dart';

part 'mapping_input.g.dart';

@JsonSerializable()
class MappingInput {
  const MappingInput({
    required this.columns,
    required this.entity,
    required this.name,
  });
  
  factory MappingInput.fromJson(Map<String, Object?> json) => _$MappingInputFromJson(json);
  
  final List<ColumnPair> columns;
  final String entity;

  /// Saving under an existing name replaces that mapping.
  final String name;

  Map<String, Object?> toJson() => _$MappingInputToJson(this);
}
