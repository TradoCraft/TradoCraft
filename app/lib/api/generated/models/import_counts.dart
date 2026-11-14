// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'import_counts.g.dart';

@JsonSerializable()
class ImportCounts {
  const ImportCounts({
    required this.bell,
    required this.bellGroup,
    required this.clockDial,
  });
  
  factory ImportCounts.fromJson(Map<String, Object?> json) => _$ImportCountsFromJson(json);
  
  final int bell;
  @JsonKey(name: 'bell_group')
  final int bellGroup;
  @JsonKey(name: 'clock_dial')
  final int clockDial;

  Map<String, Object?> toJson() => _$ImportCountsToJson(this);
}
