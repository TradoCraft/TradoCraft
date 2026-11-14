// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'lead_input.g.dart';

@JsonSerializable()
class LeadInput {
  const LeadInput({
    this.expectedValue,
    this.title,
  });
  
  factory LeadInput.fromJson(Map<String, Object?> json) => _$LeadInputFromJson(json);
  
  @JsonKey(includeIfNull: false,name: 'expected_value')
  final String? expectedValue;

  /// Defaults to the ticket subject.
  @JsonKey(includeIfNull: false)
  final String? title;

  Map<String, Object?> toJson() => _$LeadInputToJson(this);
}
