// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

/// Comparison operator of a filter.
@JsonEnum()
enum ReportOp {
  @JsonValue('eq')
  eq('eq'),
  @JsonValue('ne')
  ne('ne'),
  @JsonValue('gt')
  gt('gt'),
  @JsonValue('gte')
  gte('gte'),
  @JsonValue('lt')
  lt('lt'),
  @JsonValue('lte')
  lte('lte'),
  @JsonValue('contains')
  contains('contains'),
  @JsonValue('starts_with')
  startsWith('starts_with'),
  /// The name has been replaced because it contains a keyword. Original name: `in`.
  @JsonValue('in')
  valueIn('in'),
  @JsonValue('is_null')
  isNull('is_null'),
  @JsonValue('not_null')
  notNull('not_null'),
  /// Default value for all unparsed values, allows backward compatibility when adding new values on the backend.
  $unknown(null);

  const ReportOp(this.json);

  factory ReportOp.fromJson(String json) => values.firstWhere(
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
  static List<ReportOp> get $valuesDefined => values.where((value) => value != $unknown).toList();
}
