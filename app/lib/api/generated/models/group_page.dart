// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'group_count.dart';

part 'group_page.g.dart';

/// The response of a groups endpoint, ordered by value.
@JsonSerializable()
class GroupPage {
  const GroupPage({
    required this.groupBy,
    required this.groups,
  });
  
  factory GroupPage.fromJson(Map<String, Object?> json) => _$GroupPageFromJson(json);
  
  @JsonKey(name: 'group_by')
  final String groupBy;
  final List<GroupCount> groups;

  Map<String, Object?> toJson() => _$GroupPageToJson(this);
}
