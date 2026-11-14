// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'error_body.g.dart';

/// Error body returned by every endpoint.
@JsonSerializable()
class ErrorBody {
  const ErrorBody({
    required this.error,
    required this.message,
    this.code,
  });
  
  factory ErrorBody.fromJson(Map<String, Object?> json) => _$ErrorBodyFromJson(json);
  
  /// Stable identifier for errors a client must tell apart (for example `repair_status_changed`);.
  /// absent for the rest.
  @JsonKey(includeIfNull: false)
  final String? code;

  /// Machine-readable code: unauthorized, forbidden, not_found, validation, conflict, internal.
  final String error;
  final String message;

  Map<String, Object?> toJson() => _$ErrorBodyToJson(this);
}
