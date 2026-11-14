// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'call_input.g.dart';

/// A phone call, logged on a ticket (existing or new).
@JsonSerializable()
class CallInput {
  const CallInput({
    required this.direction,
    required this.summary,
    this.category,
    this.contactId,
    this.customerId,
    this.durationSeconds,
    this.phoneNumber,
    this.subject,
    this.ticketId,
  });
  
  factory CallInput.fromJson(Map<String, Object?> json) => _$CallInputFromJson(json);
  
  /// New ticket only.
  @JsonKey(includeIfNull: false)
  final String? category;

  /// Who it was. Defaults to the contact with this phone number, if there is exactly one.
  @JsonKey(includeIfNull: false,name: 'contact_id')
  final String? contactId;

  /// New ticket only, for a caller who is not a known contact yet.
  @JsonKey(includeIfNull: false,name: 'customer_id')
  final String? customerId;

  /// in (the customer called us) | out (we called the customer)
  final String direction;
  @JsonKey(includeIfNull: false,name: 'duration_seconds')
  final int? durationSeconds;

  /// The number that called or was called, in any format. Used to find the person when.
  /// `contact_id` is not given.
  @JsonKey(includeIfNull: false,name: 'phone_number')
  final String? phoneNumber;

  /// New ticket only; defaults to the first line of the summary.
  @JsonKey(includeIfNull: false)
  final String? subject;

  /// What was discussed.
  final String summary;

  /// Add to this ticket; without it a new ticket is opened.
  @JsonKey(includeIfNull: false,name: 'ticket_id')
  final String? ticketId;

  Map<String, Object?> toJson() => _$CallInputToJson(this);
}
