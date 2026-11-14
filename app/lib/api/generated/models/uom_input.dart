// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'uom_input.g.dart';

@JsonSerializable()
class UomInput {
  const UomInput({
    required this.category,
    required this.code,
    required this.factor,
    required this.name,
  });
  
  factory UomInput.fromJson(Map<String, Object?> json) => _$UomInputFromJson(json);
  
  final String category;
  final String code;
  final String factor;
  final String name;

  Map<String, Object?> toJson() => _$UomInputToJson(this);
}
