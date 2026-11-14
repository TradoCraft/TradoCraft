// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'login_link_input.g.dart';

@JsonSerializable()
class LoginLinkInput {
  const LoginLinkInput({
    required this.companyId,
    required this.email,
  });
  
  factory LoginLinkInput.fromJson(Map<String, Object?> json) => _$LoginLinkInputFromJson(json);
  
  /// The company whose portal this is.
  @JsonKey(name: 'company_id')
  final String companyId;
  final String email;

  Map<String, Object?> toJson() => _$LoginLinkInputToJson(this);
}
