// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'item_result.dart';

part 'item_table_result.g.dart';

@JsonSerializable()
class ItemTableResult {
  const ItemTableResult({
    required this.rows,
    required this.table,
  });
  
  factory ItemTableResult.fromJson(Map<String, Object?> json) => _$ItemTableResultFromJson(json);
  
  final List<ItemResult> rows;
  final String table;

  Map<String, Object?> toJson() => _$ItemTableResultToJson(this);
}
