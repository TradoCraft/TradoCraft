// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'import_warning.g.dart';

/// Something in the source that could not be used as is. The import carries on.
@JsonSerializable()
class ImportWarning {
  const ImportWarning({
    required this.field,
    required this.message,
    this.bell,
  });
  
  factory ImportWarning.fromJson(Map<String, Object?> json) => _$ImportWarningFromJson(json);
  
  /// Identifier of the bell, `None` for a warning about the document.
  @JsonKey(includeIfNull: false)
  final String? bell;

  /// Source field the warning is about.
  final String field;
  final String message;

  Map<String, Object?> toJson() => _$ImportWarningToJson(this);
}
