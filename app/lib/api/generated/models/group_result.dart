// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'value_result.dart';

part 'group_result.g.dart';

@JsonSerializable()
class GroupResult {
  const GroupResult({
    required this.name,
    required this.values,
  });
  
  factory GroupResult.fromJson(Map<String, Object?> json) => _$GroupResultFromJson(json);
  
  final String name;
  final List<ValueResult> values;

  Map<String, Object?> toJson() => _$GroupResultToJson(this);
}
