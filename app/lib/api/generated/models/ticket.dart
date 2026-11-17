// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'ticket_sla.dart';

part 'ticket.g.dart';

@JsonSerializable()
class Ticket {
  const Ticket({
    required this.updatedAt,
    required this.category,
    required this.checklistDone,
    required this.checklistTotal,
    required this.contactEmail,
    required this.contactName,
    required this.createdAt,
    required this.articleCount,
    required this.id,
    required this.internal,
    required this.language,
    required this.languageSource,
    required this.number,
    required this.watching,
    required this.priority,
    required this.sla,
    required this.status,
    required this.subject,
    required this.tags,
    required this.timeMinutes,
    required this.unread,
    this.escalatedByName,
    this.mergedIntoId,
    this.mergedIntoNumber,
    this.customerId,
    this.opportunityId,
    this.opportunityNumber,
    this.orderId,
    this.orderNumber,
    this.ownerName,
    this.customerName,
    this.escalatedAt,
    this.quotationId,
    this.quotationNumber,
    this.quotationRevision,
    this.quotationStatus,
    this.escalatedBy,
    this.closedAt,
    this.firstResponseAt,
    this.suggestedCategory,
    this.contactId,
    this.teamId,
    this.teamName,
    this.csatComment,
    this.csatRatedAt,
    this.csatRating,
    this.ownerUserId,
  });
  
  factory Ticket.fromJson(Map<String, Object?> json) => _$TicketFromJson(json);
  
  @JsonKey(name: 'article_count')
  final int articleCount;

  /// question | lead | quote_change | order_confirmation | production_question | service | complaint | other
  final String category;
  @JsonKey(name: 'checklist_done')
  final int checklistDone;
  @JsonKey(name: 'checklist_total')
  final int checklistTotal;
  @JsonKey(includeIfNull: false,name: 'closed_at')
  final DateTime? closedAt;
  @JsonKey(name: 'contact_email')
  final String contactEmail;

  /// The person at the customer this ticket is about (see the contacts of the customer).
  @JsonKey(includeIfNull: false,name: 'contact_id')
  final String? contactId;
  @JsonKey(name: 'contact_name')
  final String contactName;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @JsonKey(includeIfNull: false,name: 'csat_comment')
  final String? csatComment;
  @JsonKey(includeIfNull: false,name: 'csat_rated_at')
  final DateTime? csatRatedAt;

  /// The customer's latest satisfaction rating: good | bad.
  @JsonKey(includeIfNull: false,name: 'csat_rating')
  final String? csatRating;
  @JsonKey(includeIfNull: false,name: 'customer_id')
  final String? customerId;
  @JsonKey(includeIfNull: false,name: 'customer_name')
  final String? customerName;

  /// Set when a colleague escalated the ticket by hand.
  @JsonKey(includeIfNull: false,name: 'escalated_at')
  final DateTime? escalatedAt;
  @JsonKey(includeIfNull: false,name: 'escalated_by')
  final String? escalatedBy;
  @JsonKey(includeIfNull: false,name: 'escalated_by_name')
  final String? escalatedByName;
  @JsonKey(includeIfNull: false,name: 'first_response_at')
  final DateTime? firstResponseAt;
  final String id;
  final bool internal;

  /// nl | fr | en | de | es — the language to answer in.
  final String language;

  /// record | detected | agent: where `language` came from.
  @JsonKey(name: 'language_source')
  final String languageSource;

  /// Set when this ticket was merged into another one (it is closed).
  @JsonKey(includeIfNull: false,name: 'merged_into_id')
  final String? mergedIntoId;
  @JsonKey(includeIfNull: false,name: 'merged_into_number')
  final String? mergedIntoNumber;
  final String number;
  @JsonKey(includeIfNull: false,name: 'opportunity_id')
  final String? opportunityId;
  @JsonKey(includeIfNull: false,name: 'opportunity_number')
  final String? opportunityNumber;
  @JsonKey(includeIfNull: false,name: 'order_id')
  final String? orderId;
  @JsonKey(includeIfNull: false,name: 'order_number')
  final String? orderNumber;
  @JsonKey(includeIfNull: false,name: 'owner_name')
  final String? ownerName;
  @JsonKey(includeIfNull: false,name: 'owner_user_id')
  final String? ownerUserId;

  /// low | normal | high | urgent
  final String priority;
  @JsonKey(includeIfNull: false,name: 'quotation_id')
  final String? quotationId;
  @JsonKey(includeIfNull: false,name: 'quotation_number')
  final String? quotationNumber;
  @JsonKey(includeIfNull: false,name: 'quotation_revision')
  final int? quotationRevision;
  @JsonKey(includeIfNull: false,name: 'quotation_status')
  final String? quotationStatus;

  /// Due times, breach flags and minutes remaining.
  final TicketSla sla;

  /// new | open | pending_customer | pending_internal | closed
  final String status;
  final String subject;

  /// What the system guessed from the last incoming e-mail.
  @JsonKey(includeIfNull: false,name: 'suggested_category')
  final String? suggestedCategory;
  final List<String> tags;

  /// The queue the ticket waits in (the owner is the person working on it).
  @JsonKey(includeIfNull: false,name: 'team_id')
  final String? teamId;
  @JsonKey(includeIfNull: false,name: 'team_name')
  final String? teamName;

  /// Total logged time in minutes.
  @JsonKey(name: 'time_minutes')
  final int timeMinutes;

  /// For the caller: there is activity by others since they last read the ticket and they are.
  /// involved (see `collab`). Filled by the list and by `GET /tickets/{id}`.
  final bool unread;
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  /// For the caller: they follow the ticket. Filled like `unread`.
  final bool watching;

  Map<String, Object?> toJson() => _$TicketToJson(this);
}
