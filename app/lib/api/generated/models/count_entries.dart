// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'count_entry.dart';

part 'count_entries.g.dart';

@JsonSerializable()
class CountEntries {
  const CountEntries({
    required this.entries,
  });
  
  factory CountEntries.fromJson(Map<String, Object?> json) => _$CountEntriesFromJson(json);
  
  final List<CountEntry> entries;

  Map<String, Object?> toJson() => _$CountEntriesToJson(this);
}
