// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'linked_ticket.dart';

part 'ticket_links.g.dart';

/// All links of one ticket, grouped by how the ticket stands to the other one.
@JsonSerializable()
class TicketLinks {
  const TicketLinks({
    required this.children,
    required this.duplicates,
    required this.related,
    this.duplicateOf,
    this.parent,
  });
  
  factory TicketLinks.fromJson(Map<String, Object?> json) => _$TicketLinksFromJson(json);
  
  /// Tickets in the bundle of this ticket (it is their parent).
  final List<LinkedTicket> children;

  /// This ticket is a duplicate of this one.
  @JsonKey(includeIfNull: false,name: 'duplicate_of')
  final LinkedTicket? duplicateOf;

  /// Tickets that are duplicates of this one.
  final List<LinkedTicket> duplicates;

  /// This ticket is a child of the bundle of this parent.
  @JsonKey(includeIfNull: false)
  final LinkedTicket? parent;
  final List<LinkedTicket> related;

  Map<String, Object?> toJson() => _$TicketLinksToJson(this);
}
