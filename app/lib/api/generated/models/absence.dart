// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'absence.g.dart';

@JsonSerializable()
class Absence {
  const Absence({
    required this.fromDate,
    required this.id,
    required this.kind,
    required this.note,
    required this.toDate,
    required this.userId,
    required this.userName,
  });
  
  factory Absence.fromJson(Map<String, Object?> json) => _$AbsenceFromJson(json);
  
  @JsonKey(name: 'from_date')
  final DateTime fromDate;
  final String id;

  /// vacation | sick | training | other
  final String kind;
  final String note;

  /// Inclusive.
  @JsonKey(name: 'to_date')
  final DateTime toDate;
  @JsonKey(name: 'user_id')
  final String userId;
  @JsonKey(name: 'user_name')
  final String userName;

  Map<String, Object?> toJson() => _$AbsenceToJson(this);
}
