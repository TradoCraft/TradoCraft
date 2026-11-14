// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'new_ticket.g.dart';

@JsonSerializable()
class NewTicket {
  const NewTicket({
    required this.body,
    required this.subject,
    this.category,
  });
  
  factory NewTicket.fromJson(Map<String, Object?> json) => _$NewTicketFromJson(json);
  
  final String body;

  /// question | service | complaint | other
  @JsonKey(includeIfNull: false)
  final String? category;
  final String subject;

  Map<String, Object?> toJson() => _$NewTicketToJson(this);
}
