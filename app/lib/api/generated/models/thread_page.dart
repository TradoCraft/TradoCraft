// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'thread_item.dart';

part 'thread_page.g.dart';

@JsonSerializable()
class ThreadPage {
  const ThreadPage({
    required this.items,
    this.nextBeforeId,
  });
  
  factory ThreadPage.fromJson(Map<String, Object?> json) => _$ThreadPageFromJson(json);
  
  final List<ThreadItem> items;

  /// Pass as `before_id` for the next (older) page; absent on the last page.
  @JsonKey(includeIfNull: false,name: 'next_before_id')
  final String? nextBeforeId;

  Map<String, Object?> toJson() => _$ThreadPageToJson(this);
}
