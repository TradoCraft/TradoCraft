// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'findings_input.g.dart';

@JsonSerializable()
class FindingsInput {
  const FindingsInput({
    required this.findings,
    this.diagnosis,
  });
  
  factory FindingsInput.fromJson(Map<String, Object?> json) => _$FindingsInputFromJson(json);
  
  /// The department's conclusion; leave out to keep it as it is.
  @JsonKey(includeIfNull: false)
  final String? diagnosis;

  /// What was found when the parcel was looked at, and what is wrong.
  final String findings;

  Map<String, Object?> toJson() => _$FindingsInputToJson(this);
}
