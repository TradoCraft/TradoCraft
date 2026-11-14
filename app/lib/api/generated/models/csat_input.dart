// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'csat_input.g.dart';

@JsonSerializable()
class CsatInput {
  const CsatInput({
    required this.rating,
    this.comment,
  });
  
  factory CsatInput.fromJson(Map<String, Object?> json) => _$CsatInputFromJson(json);
  
  @JsonKey(includeIfNull: false)
  final String? comment;

  /// good | bad
  final String rating;

  Map<String, Object?> toJson() => _$CsatInputToJson(this);
}
