// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'link_relation.dart';

part 'link_input.g.dart';

@JsonSerializable()
class LinkInput {
  const LinkInput({
    required this.relation,
    required this.targetId,
  });
  
  factory LinkInput.fromJson(Map<String, Object?> json) => _$LinkInputFromJson(json);
  
  final LinkRelation relation;
  @JsonKey(name: 'target_id')
  final String targetId;

  Map<String, Object?> toJson() => _$LinkInputToJson(this);
}
