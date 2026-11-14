// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'value_result.dart';

part 'item_result.g.dart';

@JsonSerializable()
class ItemResult {
  const ItemResult({
    required this.group,
    required this.index,
    required this.label,
    required this.values,
  });
  
  factory ItemResult.fromJson(Map<String, Object?> json) => _$ItemResultFromJson(json);
  
  final String group;

  /// 1-based row number.
  final int index;
  final String label;
  final List<ValueResult> values;

  Map<String, Object?> toJson() => _$ItemResultToJson(this);
}
