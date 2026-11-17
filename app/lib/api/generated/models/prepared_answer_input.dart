// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'answer_text.dart';

part 'prepared_answer_input.g.dart';

@JsonSerializable()
class PreparedAnswerInput {
  const PreparedAnswerInput({
    required this.code,
    required this.name,
    required this.texts,
    this.active,
    this.category,
    this.keywords,
    this.kind,
    this.teamId,
  });
  
  factory PreparedAnswerInput.fromJson(Map<String, Object?> json) => _$PreparedAnswerInputFromJson(json);
  
  @JsonKey(includeIfNull: false)
  final bool? active;
  @JsonKey(includeIfNull: false)
  final String? category;
  final String code;
  @JsonKey(includeIfNull: false)
  final List<String>? keywords;
  @JsonKey(includeIfNull: false)
  final String? kind;
  final String name;
  @JsonKey(includeIfNull: false,name: 'team_id')
  final String? teamId;

  /// At least one language; missing languages fall back to English, then any other.
  final List<AnswerText> texts;

  Map<String, Object?> toJson() => _$PreparedAnswerInputToJson(this);
}
