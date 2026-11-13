// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'production_operation_finish.g.dart';

/// Records that an operation is finished and how many minutes it took.
@JsonSerializable()
class ProductionOperationFinish {
  const ProductionOperationFinish({
    this.actualMinutes,
    this.note,
  });
  
  factory ProductionOperationFinish.fromJson(Map<String, Object?> json) => _$ProductionOperationFinishFromJson(json);
  
  /// Total minutes worked on the operation; defaults to the planned minutes.
  @JsonKey(includeIfNull: false,name: 'actual_minutes')
  final int? actualMinutes;

  /// Added to the notes of the operation.
  @JsonKey(includeIfNull: false)
  final String? note;

  Map<String, Object?> toJson() => _$ProductionOperationFinishToJson(this);
}
