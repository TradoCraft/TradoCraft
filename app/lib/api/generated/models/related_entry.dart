// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'related_entry.g.dart';

@JsonSerializable()
class RelatedEntry {
  const RelatedEntry({
    required this.id,
    required this.number,
    required this.status,
    required this.title,
  });
  
  factory RelatedEntry.fromJson(Map<String, Object?> json) => _$RelatedEntryFromJson(json);
  
  final String id;
  final String number;
  final String status;
  final String title;

  Map<String, Object?> toJson() => _$RelatedEntryToJson(this);
}
