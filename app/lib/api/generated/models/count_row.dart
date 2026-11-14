// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'count_row.g.dart';

@JsonSerializable()
class CountRow {
  const CountRow({
    required this.count,
    required this.key,
    required this.label,
  });
  
  factory CountRow.fromJson(Map<String, Object?> json) => _$CountRowFromJson(json);
  
  final int count;

  /// The value (status, priority, category, tag) or an id for teams and owners; empty = none.
  final String key;
  final String label;

  Map<String, Object?> toJson() => _$CountRowToJson(this);
}
