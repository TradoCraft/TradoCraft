// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'oidc_subject_input.g.dart';

/// The settings of the user's identity: the issuer-qualified subject to set, or none to clear it.
@JsonSerializable()
class OidcSubjectInput {
  const OidcSubjectInput({this.issuer, this.subject});

  factory OidcSubjectInput.fromJson(Map<String, Object?> json) =>
      _$OidcSubjectInputFromJson(json);

  /// Issuer of a configured database provider.
  @JsonKey(includeIfNull: false)
  final String? issuer;

  /// The `sub` the provider uses for this person; none clears the binding.
  @JsonKey(includeIfNull: false)
  final String? subject;

  Map<String, Object?> toJson() => _$OidcSubjectInputToJson(this);
}
