// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'mrp_run_input.g.dart';

@JsonSerializable()
class MrpRunInput {
  const MrpRunInput({
    this.horizonDays,
  });
  
  factory MrpRunInput.fromJson(Map<String, Object?> json) => _$MrpRunInputFromJson(json);
  
  /// How many days ahead to plan; default 90, at most 730.
  @JsonKey(includeIfNull: false,name: 'horizon_days')
  final int? horizonDays;

  Map<String, Object?> toJson() => _$MrpRunInputToJson(this);
}
