// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'absence_input.g.dart';

@JsonSerializable()
class AbsenceInput {
  const AbsenceInput({
    required this.fromDate,
    required this.kind,
    required this.toDate,
    required this.userId,
    this.note,
  });
  
  factory AbsenceInput.fromJson(Map<String, Object?> json) => _$AbsenceInputFromJson(json);
  
  @JsonKey(name: 'from_date')
  final DateTime fromDate;
  final String kind;
  @JsonKey(includeIfNull: false)
  final String? note;
  @JsonKey(name: 'to_date')
  final DateTime toDate;
  @JsonKey(name: 'user_id')
  final String userId;

  Map<String, Object?> toJson() => _$AbsenceInputToJson(this);
}
