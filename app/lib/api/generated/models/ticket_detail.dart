// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'article.dart';
import 'reader.dart';
import 'ticket.dart';
import 'watcher.dart';

part 'ticket_detail.g.dart';

@JsonSerializable()
class TicketDetail {
  const TicketDetail({
    required this.articles,
    required this.readers,
    required this.ticket,
    required this.watchers,
  });
  
  factory TicketDetail.fromJson(Map<String, Object?> json) => _$TicketDetailFromJson(json);
  
  final List<Article> articles;

  /// Colleagues who opened the ticket, most recent first ("seen by").
  final List<Reader> readers;
  final Ticket ticket;

  /// Colleagues who follow the ticket.
  final List<Watcher> watchers;

  Map<String, Object?> toJson() => _$TicketDetailToJson(this);
}
