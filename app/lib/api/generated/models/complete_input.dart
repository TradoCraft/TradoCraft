// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'complete_input.g.dart';

@JsonSerializable()
class CompleteInput {
  const CompleteInput({
    required this.notes,
  });
  
  factory CompleteInput.fromJson(Map<String, Object?> json) => _$CompleteInputFromJson(json);
  
  /// What was done, and anything left open.
  final String notes;

  Map<String, Object?> toJson() => _$CompleteInputToJson(this);
}
