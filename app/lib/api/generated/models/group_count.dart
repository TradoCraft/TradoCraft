// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'group_count.g.dart';

/// The rows of one group.
@JsonSerializable()
class GroupCount {
  const GroupCount({
    required this.count,
    required this.value,
  });
  
  factory GroupCount.fromJson(Map<String, Object?> json) => _$GroupCountFromJson(json);
  
  final int count;

  /// The group value as text (booleans as `true` / `false`).
  final String value;

  Map<String, Object?> toJson() => _$GroupCountToJson(this);
}
