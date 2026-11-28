// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

/// What an import does with a position that names fewer groups than the list's group levels.
@JsonEnum()
enum ImportShortPosition {
  @JsonValue('shallower_group')
  shallowerGroup('shallower_group'),
  @JsonValue('error')
  error('error'),
  /// Default value for all unparsed values, allows backward compatibility when adding new values on the backend.
  $unknown(null);

  const ImportShortPosition(this.json);

  factory ImportShortPosition.fromJson(String json) => values.firstWhere(
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
  static List<ImportShortPosition> get $valuesDefined => values.where((value) => value != $unknown).toList();
}
