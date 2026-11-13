// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'binding_result.g.dart';

/// What signing in with the sample token would do.
@JsonSerializable()
class BindingResult {
  const BindingResult({
    required this.outcome,
    this.reason,
    this.userEmail,
    this.userId,
  });
  
  factory BindingResult.fromJson(Map<String, Object?> json) => _$BindingResultFromJson(json);
  
  /// `existing_subject`, `would_bind` or `refused`.
  final String outcome;

  /// Why it is refused.
  @JsonKey(includeIfNull: false)
  final String? reason;

  /// That user's e-mail address.
  @JsonKey(includeIfNull: false,name: 'user_email')
  final String? userEmail;

  /// The user it resolves to.
  @JsonKey(includeIfNull: false,name: 'user_id')
  final String? userId;

  Map<String, Object?> toJson() => _$BindingResultToJson(this);
}
