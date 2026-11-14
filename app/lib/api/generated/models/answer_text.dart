// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'answer_text.g.dart';

@JsonSerializable()
class AnswerText {
  const AnswerText({
    required this.body,
    required this.language,
    this.subject,
  });
  
  factory AnswerText.fromJson(Map<String, Object?> json) => _$AnswerTextFromJson(json);
  
  final String body;

  /// nl | fr | en | de | es
  final String language;
  @JsonKey(includeIfNull: false)
  final String? subject;

  Map<String, Object?> toJson() => _$AnswerTextToJson(this);
}
