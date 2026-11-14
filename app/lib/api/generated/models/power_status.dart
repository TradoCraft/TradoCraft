// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

/// Machine-readable status of a [`PowerCompatibility`].
@JsonEnum()
enum PowerStatus {
  @JsonValue('not_applicable')
  notApplicable('not_applicable'),
  @JsonValue('needs_external_supply')
  needsExternalSupply('needs_external_supply'),
  @JsonValue('compatible')
  compatible('compatible'),
  @JsonValue('incompatible')
  incompatible('incompatible'),
  @JsonValue('unknown_grid')
  unknownGrid('unknown_grid'),
  /// Default value for all unparsed values, allows backward compatibility when adding new values on the backend.
  $unknown(null);

  const PowerStatus(this.json);

  factory PowerStatus.fromJson(String json) => values.firstWhere(
        (e) => e.json == json,
        orElse: () => $unknown,
      );

  final String? json;
  String toJson() {
    final value = json;
    if (value == null) {
      throw StateError('Cannot convert enum value with null JSON representation to String. '
          'This usually happens for \$unknown or @JsonValue(null) entries.');
    }
    return value as String;
  }

  @override
  String toString() => json?.toString() ?? super.toString();
  /// Returns all defined enum values excluding the $unknown value.
  static List<PowerStatus> get $valuesDefined => values.where((value) => value != $unknown).toList();
}
