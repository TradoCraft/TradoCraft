// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'rule_action.g.dart';

/// One change a rule makes. `kind` decides which of the other fields is used:.
/// `set_owner` (`user_id`), `set_team` (`team_id`), `set_priority` (`value`), `set_category`.
/// (`value`), `add_tag` (`value`), `set_internal` (`flag`), `send_email` (`recipient`, `team_id` or.
/// `address`, `subject`, `body`, `period_hours`; ADR 0066).
@JsonSerializable()
class RuleAction {
  const RuleAction({
    required this.kind,
    this.address,
    this.body,
    this.flag,
    this.periodHours,
    this.recipient,
    this.subject,
    this.teamId,
    this.userId,
    this.value,
  });
  
  factory RuleAction.fromJson(Map<String, Object?> json) => _$RuleActionFromJson(json);
  
  /// `send_email` to `address`: the fixed recipient.
  @JsonKey(includeIfNull: false)
  final String? address;

  /// `send_email`: the text, with the same placeholders.
  @JsonKey(includeIfNull: false)
  final String? body;
  @JsonKey(includeIfNull: false)
  final bool? flag;
  final String kind;

  /// `send_email`: at most one mail per ticket and rule in this many hours (default 24).
  @JsonKey(includeIfNull: false,name: 'period_hours')
  final int? periodHours;

  /// `send_email`: customer | assignee | team | address.
  @JsonKey(includeIfNull: false)
  final String? recipient;

  /// `send_email`: one line; `{ticket_number}`, `{subject}`, `{customer}`, `{agent}` are replaced.
  @JsonKey(includeIfNull: false)
  final String? subject;
  @JsonKey(includeIfNull: false,name: 'team_id')
  final String? teamId;
  @JsonKey(includeIfNull: false,name: 'user_id')
  final String? userId;
  @JsonKey(includeIfNull: false)
  final String? value;

  Map<String, Object?> toJson() => _$RuleActionToJson(this);
}
