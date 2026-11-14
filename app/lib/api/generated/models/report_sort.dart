// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'report_dir.dart';

part 'report_sort.g.dart';

/// A sort key, naming an output column.
@JsonSerializable()
class ReportSort {
  const ReportSort({
    required this.column,
    this.dir,
  });
  
  factory ReportSort.fromJson(Map<String, Object?> json) => _$ReportSortFromJson(json);
  
  /// Output column key, see the module documentation.
  final String column;
  @JsonKey(includeIfNull: false)
  final ReportDir? dir;

  Map<String, Object?> toJson() => _$ReportSortToJson(this);
}
