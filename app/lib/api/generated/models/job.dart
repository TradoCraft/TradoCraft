// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'technician.dart';

part 'job.g.dart';

@JsonSerializable()
class Job {
  const Job({
    required this.street,
    required this.city,
    required this.completionNotes,
    required this.id,
    required this.countryCode,
    required this.customerId,
    required this.customerName,
    required this.address,
    required this.instructions,
    required this.kind,
    required this.number,
    required this.postalCode,
    required this.status,
    required this.tasksTotal,
    required this.technicians,
    required this.reportSentTo,
    required this.title,
    required this.priority,
    required this.tasksDone,
    required this.siteName,
    this.contactName,
    this.repairId,
    this.longitude,
    this.latitude,
    this.scheduledEnd,
    this.scheduledStart,
    this.dueDate,
    this.startedAt,
    this.contractNumber,
    this.reportSentAt,
    this.contractId,
    this.contactId,
    this.completedAt,
    this.ticketId,
    this.mapsUrl,
  });
  
  factory Job.fromJson(Map<String, Object?> json) => _$JobFromJson(json);
  
  /// The address on one line.
  final String address;
  final String city;
  @JsonKey(includeIfNull: false,name: 'completed_at')
  final DateTime? completedAt;
  @JsonKey(name: 'completion_notes')
  final String completionNotes;

  /// The person to meet on site.
  @JsonKey(includeIfNull: false,name: 'contact_id')
  final String? contactId;
  @JsonKey(includeIfNull: false,name: 'contact_name')
  final String? contactName;

  /// The maintenance contract this job was generated for.
  @JsonKey(includeIfNull: false,name: 'contract_id')
  final String? contractId;
  @JsonKey(includeIfNull: false,name: 'contract_number')
  final String? contractNumber;
  @JsonKey(name: 'country_code')
  final String countryCode;
  @JsonKey(name: 'customer_id')
  final String customerId;
  @JsonKey(name: 'customer_name')
  final String customerName;

  /// The day a contract visit is due.
  @JsonKey(includeIfNull: false,name: 'due_date')
  final DateTime? dueDate;
  final String id;

  /// What has to be done there.
  final String instructions;

  /// installation | maintenance | repair | inspection | other
  final String kind;
  @JsonKey(includeIfNull: false)
  final double? latitude;
  @JsonKey(includeIfNull: false)
  final double? longitude;

  /// Opens navigation to the site.
  @JsonKey(includeIfNull: false,name: 'maps_url')
  final String? mapsUrl;
  final String number;
  @JsonKey(name: 'postal_code')
  final String postalCode;
  final String priority;
  @JsonKey(includeIfNull: false,name: 'repair_id')
  final String? repairId;

  /// When the service report was last e-mailed to the customer.
  @JsonKey(includeIfNull: false,name: 'report_sent_at')
  final DateTime? reportSentAt;
  @JsonKey(name: 'report_sent_to')
  final String reportSentTo;
  @JsonKey(includeIfNull: false,name: 'scheduled_end')
  final DateTime? scheduledEnd;
  @JsonKey(includeIfNull: false,name: 'scheduled_start')
  final DateTime? scheduledStart;
  @JsonKey(name: 'site_name')
  final String siteName;
  @JsonKey(includeIfNull: false,name: 'started_at')
  final DateTime? startedAt;

  /// planned | in_progress | completed | cancelled
  final String status;
  final String street;
  @JsonKey(name: 'tasks_done')
  final int tasksDone;
  @JsonKey(name: 'tasks_total')
  final int tasksTotal;
  final List<Technician> technicians;
  @JsonKey(includeIfNull: false,name: 'ticket_id')
  final String? ticketId;
  final String title;

  Map<String, Object?> toJson() => _$JobToJson(this);
}
