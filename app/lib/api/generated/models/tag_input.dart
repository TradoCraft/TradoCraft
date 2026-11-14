// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'tag_input.g.dart';

@JsonSerializable()
class TagInput {
  const TagInput({
    required this.tag,
  });
  
  factory TagInput.fromJson(Map<String, Object?> json) => _$TagInputFromJson(json);
  
  final String tag;

  Map<String, Object?> toJson() => _$TagInputToJson(this);
}
