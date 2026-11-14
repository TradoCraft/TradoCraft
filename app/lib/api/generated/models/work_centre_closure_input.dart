// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'work_centre_closure_input.g.dart';

@JsonSerializable()
class WorkCentreClosureInput {
  const WorkCentreClosureInput({
    required this.fromDate,
    required this.toDate,
    this.kind,
    this.note,
    this.workCentreId,
  });
  
  factory WorkCentreClosureInput.fromJson(Map<String, Object?> json) => _$WorkCentreClosureInputFromJson(json);
  
  @JsonKey(name: 'from_date')
  final DateTime fromDate;

  /// maintenance | holiday | other
  @JsonKey(includeIfNull: false)
  final String? kind;
  @JsonKey(includeIfNull: false)
  final String? note;

  /// Inclusive.
  @JsonKey(name: 'to_date')
  final DateTime toDate;

  /// Leave empty to close the whole plant.
  @JsonKey(includeIfNull: false,name: 'work_centre_id')
  final String? workCentreId;

  Map<String, Object?> toJson() => _$WorkCentreClosureInputToJson(this);
}
