// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'unmapped_field.g.dart';

/// A source field that has no baseline attribute. It is kept in the item's `source_data`.
@JsonSerializable()
class UnmappedField {
  const UnmappedField({
    required this.count,
    required this.field,
  });
  
  factory UnmappedField.fromJson(Map<String, Object?> json) => _$UnmappedFieldFromJson(json);
  
  /// How many bells carry it (1 for a top-level section).
  final int count;

  /// `bells[].properties.<name>`, `bells[].<name>` or a top-level section name.
  final String field;

  Map<String, Object?> toJson() => _$UnmappedFieldToJson(this);
}
