// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'kb_vote.g.dart';

@JsonSerializable()
class KbVote {
  const KbVote({
    required this.helpful,
  });
  
  factory KbVote.fromJson(Map<String, Object?> json) => _$KbVoteFromJson(json);
  
  /// true = helpful, false = not helpful
  final bool helpful;

  Map<String, Object?> toJson() => _$KbVoteToJson(this);
}
