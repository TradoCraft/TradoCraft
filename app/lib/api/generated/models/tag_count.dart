// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'tag_count.g.dart';

@JsonSerializable()
class TagCount {
  const TagCount({
    required this.count,
    required this.tag,
  });
  
  factory TagCount.fromJson(Map<String, Object?> json) => _$TagCountFromJson(json);
  
  final int count;
  final String tag;

  Map<String, Object?> toJson() => _$TagCountToJson(this);
}
