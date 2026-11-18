// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'mass_outcome.dart';

part 'mass_update_item.g.dart';

@JsonSerializable()
class MassUpdateItem {
  const MassUpdateItem({
    required this.number,
    required this.outcome,
    required this.subject,
    required this.ticketId,
    this.reason,
    this.recipient,
  });
  
  factory MassUpdateItem.fromJson(Map<String, Object?> json) => _$MassUpdateItemFromJson(json);
  
  final String number;
  final MassOutcome outcome;
  @JsonKey(includeIfNull: false)
  final String? reason;

  /// Where a reply goes.
  @JsonKey(includeIfNull: false)
  final String? recipient;
  final String subject;
  @JsonKey(name: 'ticket_id')
  final String ticketId;

  Map<String, Object?> toJson() => _$MassUpdateItemToJson(this);
}
