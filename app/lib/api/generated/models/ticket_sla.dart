// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'target_state.dart';

part 'ticket_sla.g.dart';

/// The SLA of a ticket as the API shows it.
@JsonSerializable()
class TicketSla {
  const TicketSla({
    required this.firstResponse,
    required this.firstResponseBreached,
    required this.paused,
    required this.resolution,
    required this.resolutionBreached,
    required this.state,
  });
  
  factory TicketSla.fromJson(Map<String, Object?> json) => _$TicketSlaFromJson(json);
  
  @JsonKey(name: 'first_response')
  final TargetState firstResponse;
  @JsonKey(name: 'first_response_breached')
  final bool firstResponseBreached;

  /// The clock is stopped: the ticket waits for the customer.
  final bool paused;
  final TargetState resolution;
  @JsonKey(name: 'resolution_breached')
  final bool resolutionBreached;

  /// none (no service level) | on_time | at_risk | breached
  final String state;

  Map<String, Object?> toJson() => _$TicketSlaToJson(this);
}
