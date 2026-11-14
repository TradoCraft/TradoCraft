// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'profile_input.g.dart';

/// What a customer may change about themselves: how they want to be addressed.
@JsonSerializable()
class ProfileInput {
  const ProfileInput({
    required this.addressForm,
    required this.title,
    this.language,
  });
  
  factory ProfileInput.fromJson(Map<String, Object?> json) => _$ProfileInputFromJson(json);
  
  /// formal | informal
  @JsonKey(name: 'address_form')
  final String addressForm;

  /// nl | fr | en | de | es; null = same as the company.
  @JsonKey(includeIfNull: false)
  final String? language;

  /// mr | ms | none
  final String title;

  Map<String, Object?> toJson() => _$ProfileInputToJson(this);
}
