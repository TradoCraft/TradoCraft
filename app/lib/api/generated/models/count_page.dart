// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'count.dart';

part 'count_page.g.dart';

/// A page of counts, newest first, with the number of counts that match.
@JsonSerializable()
class CountPage {
  const CountPage({
    required this.items,
    required this.total,
  });
  
  factory CountPage.fromJson(Map<String, Object?> json) => _$CountPageFromJson(json);
  
  final List<Count> items;
  final int total;

  Map<String, Object?> toJson() => _$CountPageToJson(this);
}
