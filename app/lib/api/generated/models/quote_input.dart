// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'quote_input.g.dart';

@JsonSerializable()
class QuoteInput {
  const QuoteInput({
    this.notes,
    this.purpose,
    this.validDays,
  });
  
  factory QuoteInput.fromJson(Map<String, Object?> json) => _$QuoteInputFromJson(json);
  
  /// Notes on the quotation.
  @JsonKey(includeIfNull: false)
  final String? notes;

  /// `installation` (default) or `stock`.
  @JsonKey(includeIfNull: false)
  final String? purpose;
  @JsonKey(includeIfNull: false,name: 'valid_days')
  final int? validDays;

  Map<String, Object?> toJson() => _$QuoteInputToJson(this);
}
