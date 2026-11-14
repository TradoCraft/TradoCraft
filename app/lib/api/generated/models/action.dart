// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'action.g.dart';

/// One change a rule makes. `kind` decides which of the other fields is used:.
/// `set_owner` (`user_id`), `set_team` (`team_id`), `set_priority` (`value`), `set_category`.
/// (`value`), `add_tag` (`value`), `set_internal` (`flag`).
@JsonSerializable()
class Action {
  const Action({
    required this.kind,
    this.flag,
    this.teamId,
    this.userId,
    this.value,
  });

  factory Action.fromJson(Map<String, Object?> json) => _$ActionFromJson(json);

  @JsonKey(includeIfNull: false)
  final bool? flag;
  final String kind;
  @JsonKey(includeIfNull: false, name: 'team_id')
  final String? teamId;
  @JsonKey(includeIfNull: false, name: 'user_id')
  final String? userId;
  @JsonKey(includeIfNull: false)
  final String? value;

  Map<String, Object?> toJson() => _$ActionToJson(this);
}
