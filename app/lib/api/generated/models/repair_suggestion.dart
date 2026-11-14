// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'repair.dart';

part 'repair_suggestion.g.dart';

/// An announced repair that may belong to a parcel, with why.
@JsonSerializable()
class RepairSuggestion {
  const RepairSuggestion({
    required this.reasons,
    required this.repair,
    required this.score,
  });
  
  factory RepairSuggestion.fromJson(Map<String, Object?> json) => _$RepairSuggestionFromJson(json);
  
  /// serial | customer | reference | ticket | product | recent
  final List<String> reasons;
  final Repair repair;
  final int score;

  Map<String, Object?> toJson() => _$RepairSuggestionToJson(this);
}
