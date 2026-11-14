// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'import_preview_item.g.dart';

@JsonSerializable()
class ImportPreviewItem {
  const ImportPreviewItem({
    required this.name,
    required this.typeCode,
    required this.values,
  });
  
  factory ImportPreviewItem.fromJson(Map<String, Object?> json) => _$ImportPreviewItemFromJson(json);
  
  final String name;
  @JsonKey(name: 'type_code')
  final String typeCode;

  /// Mapped attribute values keyed by definition key.
  final dynamic values;

  Map<String, Object?> toJson() => _$ImportPreviewItemToJson(this);
}
