// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'select_option.g.dart';

@JsonSerializable()
class SelectOption {
  const SelectOption({
    required this.label,
    required this.value,
  });
  
  factory SelectOption.fromJson(Map<String, Object?> json) => _$SelectOptionFromJson(json);
  
  final String label;
  final String value;

  Map<String, Object?> toJson() => _$SelectOptionToJson(this);
}
