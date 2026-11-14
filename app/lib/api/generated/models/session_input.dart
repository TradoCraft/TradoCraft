// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'session_input.g.dart';

@JsonSerializable()
class SessionInput {
  const SessionInput({
    required this.token,
  });
  
  factory SessionInput.fromJson(Map<String, Object?> json) => _$SessionInputFromJson(json);
  
  /// The token from the login link.
  final String token;

  Map<String, Object?> toJson() => _$SessionInputToJson(this);
}
