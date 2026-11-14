// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'split_input.g.dart';

@JsonSerializable()
class SplitInput {
  const SplitInput({
    required this.articleIds,
    this.subject,
  });
  
  factory SplitInput.fromJson(Map<String, Object?> json) => _$SplitInputFromJson(json);
  
  /// The messages (articles) that move to the new ticket. At least one, and not all of them.
  @JsonKey(name: 'article_ids')
  final List<String> articleIds;

  /// The subject of the new ticket; default: the subject of the first moved message, else the.
  /// subject of this ticket.
  @JsonKey(includeIfNull: false)
  final String? subject;

  Map<String, Object?> toJson() => _$SplitInputToJson(this);
}
