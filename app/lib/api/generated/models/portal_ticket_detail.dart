// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'portal_message.dart';
import 'portal_ticket.dart';

part 'portal_ticket_detail.g.dart';

@JsonSerializable()
class PortalTicketDetail {
  const PortalTicketDetail({
    required this.messages,
    required this.ticket,
  });
  
  factory PortalTicketDetail.fromJson(Map<String, Object?> json) => _$PortalTicketDetailFromJson(json);
  
  final List<PortalMessage> messages;
  final PortalTicket ticket;

  Map<String, Object?> toJson() => _$PortalTicketDetailToJson(this);
}
