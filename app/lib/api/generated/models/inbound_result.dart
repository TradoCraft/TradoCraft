// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'inbound_result.g.dart';

@JsonSerializable()
class InboundResult {
  const InboundResult({
    required this.duplicate,
    required this.newTicket,
    required this.ticketId,
    required this.ticketNumber,
  });
  
  factory InboundResult.fromJson(Map<String, Object?> json) => _$InboundResultFromJson(json);
  
  final bool duplicate;
  @JsonKey(name: 'new_ticket')
  final bool newTicket;
  @JsonKey(name: 'ticket_id')
  final String ticketId;
  @JsonKey(name: 'ticket_number')
  final String ticketNumber;

  Map<String, Object?> toJson() => _$InboundResultToJson(this);
}
