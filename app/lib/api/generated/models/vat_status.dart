// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

/// What the local rules say about the number.
@JsonEnum()
enum VatStatus {
  @JsonValue('empty')
  empty('empty'),
  @JsonValue('not_checked')
  notChecked('not_checked'),
  @JsonValue('valid')
  valid('valid'),
  @JsonValue('format_ok')
  formatOk('format_ok'),
  @JsonValue('bad_format')
  badFormat('bad_format'),
  @JsonValue('bad_checksum')
  badChecksum('bad_checksum'),

  /// Default value for all unparsed values, allows backward compatibility when adding new values on the backend.
  $unknown(null);

  const VatStatus(this.json);

  factory VatStatus.fromJson(String json) =>
      values.firstWhere((e) => e.json == json, orElse: () => $unknown);

  final String? json;
  String toJson() {
    final value = json;
    if (value == null) {
      throw StateError(
        'Cannot convert enum value with null JSON representation to String. '
        'This usually happens for \$unknown or @JsonValue(null) entries.',
      );
    }
    return value as String;
  }

  @override
  String toString() => json?.toString() ?? super.toString();

  /// Returns all defined enum values excluding the $unknown value.
  static List<VatStatus> get $valuesDefined =>
      values.where((value) => value != $unknown).toList();
}
