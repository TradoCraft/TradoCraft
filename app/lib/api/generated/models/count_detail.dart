// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'count.dart';
import 'count_line.dart';

part 'count_detail.g.dart';

@JsonSerializable()
class CountDetail {
  const CountDetail({
    required this.count,
    required this.lines,
    required this.movedDuringCount,
  });
  
  factory CountDetail.fromJson(Map<String, Object?> json) => _$CountDetailFromJson(json);
  
  final Count count;
  final List<CountLine> lines;

  /// Posted lines where the stock at posting differed from what was expected when the count.
  /// started: movements made during the count, which the count overwrote with what was counted.
  @JsonKey(name: 'moved_during_count')
  final int movedDuringCount;

  Map<String, Object?> toJson() => _$CountDetailToJson(this);
}
