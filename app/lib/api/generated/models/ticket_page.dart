// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'ticket.dart';

part 'ticket_page.g.dart';

@JsonSerializable()
class TicketPage {
  const TicketPage({
    required this.items,
    required this.total,
  });
  
  factory TicketPage.fromJson(Map<String, Object?> json) => _$TicketPageFromJson(json);
  
  final List<Ticket> items;
  final int total;

  Map<String, Object?> toJson() => _$TicketPageToJson(this);
}
