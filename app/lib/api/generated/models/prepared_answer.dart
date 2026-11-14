// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'answer_text.dart';

part 'prepared_answer.g.dart';

@JsonSerializable()
class PreparedAnswer {
  const PreparedAnswer({
    required this.active,
    required this.code,
    required this.id,
    required this.name,
    required this.texts,
    required this.updatedAt,
    this.category,
  });
  
  factory PreparedAnswer.fromJson(Map<String, Object?> json) => _$PreparedAnswerFromJson(json);
  
  final bool active;
  @JsonKey(includeIfNull: false)
  final String? category;

  /// Short code to find the answer quickly, e.g. `order-confirmed`.
  final String code;
  final String id;
  final String name;
  final List<AnswerText> texts;
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  Map<String, Object?> toJson() => _$PreparedAnswerToJson(this);
}
