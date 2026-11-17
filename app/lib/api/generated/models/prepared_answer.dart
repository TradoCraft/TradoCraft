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
    required this.keywords,
    required this.kind,
    required this.name,
    required this.texts,
    required this.updatedAt,
    this.category,
    this.teamId,
  });
  
  factory PreparedAnswer.fromJson(Map<String, Object?> json) => _$PreparedAnswerFromJson(json);
  
  final bool active;
  @JsonKey(includeIfNull: false)
  final String? category;

  /// Short code to find the answer quickly, e.g. `order-confirmed`.
  final String code;
  final String id;

  /// Lower-case words; a ticket subject containing one ranks the answer higher.
  final List<String> keywords;

  /// reply | internal_note | handover | notice
  final String kind;
  final String name;

  /// Absent: usable by every team.
  @JsonKey(includeIfNull: false,name: 'team_id')
  final String? teamId;
  final List<AnswerText> texts;
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  Map<String, Object?> toJson() => _$PreparedAnswerToJson(this);
}
