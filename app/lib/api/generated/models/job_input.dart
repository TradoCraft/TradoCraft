// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'job_input.g.dart';

@JsonSerializable()
class JobInput {
  const JobInput({
    required this.customerId,
    required this.title,
    this.city,
    this.contactId,
    this.countryCode,
    this.instructions,
    this.kind,
    this.latitude,
    this.longitude,
    this.postalCode,
    this.priority,
    this.repairId,
    this.scheduledEnd,
    this.scheduledStart,
    this.siteName,
    this.street,
    this.tasks,
    this.technicianIds,
    this.ticketId,
  });
  
  factory JobInput.fromJson(Map<String, Object?> json) => _$JobInputFromJson(json);
  
  @JsonKey(includeIfNull: false)
  final String? city;
  @JsonKey(includeIfNull: false,name: 'contact_id')
  final String? contactId;
  @JsonKey(includeIfNull: false,name: 'country_code')
  final String? countryCode;
  @JsonKey(name: 'customer_id')
  final String customerId;
  @JsonKey(includeIfNull: false)
  final String? instructions;
  @JsonKey(includeIfNull: false)
  final String? kind;
  @JsonKey(includeIfNull: false)
  final double? latitude;
  @JsonKey(includeIfNull: false)
  final double? longitude;
  @JsonKey(includeIfNull: false,name: 'postal_code')
  final String? postalCode;
  @JsonKey(includeIfNull: false)
  final String? priority;
  @JsonKey(includeIfNull: false,name: 'repair_id')
  final String? repairId;
  @JsonKey(includeIfNull: false,name: 'scheduled_end')
  final DateTime? scheduledEnd;
  @JsonKey(includeIfNull: false,name: 'scheduled_start')
  final DateTime? scheduledStart;

  /// Where to go. Left empty, the customer's address is used.
  @JsonKey(includeIfNull: false,name: 'site_name')
  final String? siteName;
  @JsonKey(includeIfNull: false)
  final String? street;

  /// The checklist; only used when creating (change it with the task endpoints).
  @JsonKey(includeIfNull: false)
  final List<String>? tasks;
  @JsonKey(includeIfNull: false,name: 'technician_ids')
  final List<String>? technicianIds;
  @JsonKey(includeIfNull: false,name: 'ticket_id')
  final String? ticketId;
  final String title;

  Map<String, Object?> toJson() => _$JobInputToJson(this);
}
