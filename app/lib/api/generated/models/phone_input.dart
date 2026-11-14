// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'phone_input.g.dart';

@JsonSerializable()
class PhoneInput {
  const PhoneInput({
    required this.number,
    this.label,
  });
  
  factory PhoneInput.fromJson(Map<String, Object?> json) => _$PhoneInputFromJson(json);
  
  /// work | mobile | direct | other
  @JsonKey(includeIfNull: false)
  final String? label;

  /// Any common format. Without a country code the customer's country is assumed.
  final String number;

  Map<String, Object?> toJson() => _$PhoneInputToJson(this);
}
