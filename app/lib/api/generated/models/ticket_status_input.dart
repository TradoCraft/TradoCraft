// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'ticket_status_input.g.dart';

/// A new status for a ticket, and nothing else.
@JsonSerializable()
class TicketStatusInput {
  const TicketStatusInput({
    required this.status,
    this.expectedVersion,
  });
  
  factory TicketStatusInput.fromJson(Map<String, Object?> json) => _$TicketStatusInputFromJson(json);
  
  /// The `version` the caller last saw. A ticket that has changed since is refused (409.
  /// `record_changed`); left out, the change always goes through (a board move).
  @JsonKey(includeIfNull: false,name: 'expected_version')
  final int? expectedVersion;

  /// new | open | pending_customer | pending_internal | closed
  final String status;

  Map<String, Object?> toJson() => _$TicketStatusInputToJson(this);
}
