// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'ticket_input.g.dart';

/// Full update of the ticket's fields and links.
@JsonSerializable()
class TicketInput {
  const TicketInput({
    required this.category,
    required this.language,
    required this.priority,
    required this.status,
    required this.subject,
    this.contactEmail,
    this.contactId,
    this.contactName,
    this.customerId,
    this.opportunityId,
    this.ownerUserId,
    this.quotationId,
  });
  
  factory TicketInput.fromJson(Map<String, Object?> json) => _$TicketInputFromJson(json);
  
  final String category;
  @JsonKey(includeIfNull: false,name: 'contact_email')
  final String? contactEmail;
  @JsonKey(includeIfNull: false,name: 'contact_id')
  final String? contactId;
  @JsonKey(includeIfNull: false,name: 'contact_name')
  final String? contactName;
  @JsonKey(includeIfNull: false,name: 'customer_id')
  final String? customerId;
  final String language;
  @JsonKey(includeIfNull: false,name: 'opportunity_id')
  final String? opportunityId;
  @JsonKey(includeIfNull: false,name: 'owner_user_id')
  final String? ownerUserId;
  final String priority;
  @JsonKey(includeIfNull: false,name: 'quotation_id')
  final String? quotationId;
  final String status;
  final String subject;

  Map<String, Object?> toJson() => _$TicketInputToJson(this);
}
