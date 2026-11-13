// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'work_centre_closure.g.dart';

/// A period in which a work centre (or the whole plant) does not work.
@JsonSerializable()
class WorkCentreClosure {
  const WorkCentreClosure({
    required this.fromDate,
    required this.id,
    required this.kind,
    required this.note,
    required this.toDate,
    this.workCentreCode,
    this.workCentreId,
  });
  
  factory WorkCentreClosure.fromJson(Map<String, Object?> json) => _$WorkCentreClosureFromJson(json);
  
  @JsonKey(name: 'from_date')
  final DateTime fromDate;
  final String id;

  /// maintenance | holiday | other
  final String kind;
  final String note;
  @JsonKey(name: 'to_date')
  final DateTime toDate;
  @JsonKey(includeIfNull: false,name: 'work_centre_code')
  final String? workCentreCode;

  /// Empty: the whole plant is closed (a holiday).
  @JsonKey(includeIfNull: false,name: 'work_centre_id')
  final String? workCentreId;

  Map<String, Object?> toJson() => _$WorkCentreClosureToJson(this);
}
