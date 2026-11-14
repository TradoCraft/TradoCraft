// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'merge_input.g.dart';

@JsonSerializable()
class MergeInput {
  const MergeInput({
    required this.targetId,
  });
  
  factory MergeInput.fromJson(Map<String, Object?> json) => _$MergeInputFromJson(json);
  
  /// The ticket that stays and receives everything.
  @JsonKey(name: 'target_id')
  final String targetId;

  Map<String, Object?> toJson() => _$MergeInputToJson(this);
}
