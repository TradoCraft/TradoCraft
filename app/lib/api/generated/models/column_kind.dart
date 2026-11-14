// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

/// What kind of value a column holds. It tells a person (and a mapping screen) how a cell is read.
/// and tells an export how to type the cell: text columns are always text cells, so `00123` and.
/// `=x` survive a spreadsheet.
@JsonEnum()
enum ColumnKind {
  @JsonValue('text')
  text('text'),
  @JsonValue('code')
  code('code'),
  @JsonValue('decimal')
  decimal('decimal'),
  @JsonValue('integer')
  integer('integer'),
  @JsonValue('boolean')
  boolean('boolean'),
  /// Default value for all unparsed values, allows backward compatibility when adding new values on the backend.
  $unknown(null);

  const ColumnKind(this.json);

  factory ColumnKind.fromJson(String json) => values.firstWhere(
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
  static List<ColumnKind> get $valuesDefined => values.where((value) => value != $unknown).toList();
}
