// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'job_equipment.dart';
import 'visit_template.dart';

part 'contract_detail.g.dart';

@JsonSerializable()
class ContractDetail {
  const ContractDetail({
    required this.autoRenew,
    required this.customerId,
    required this.customerName,
    required this.id,
    required this.number,
    required this.openJobs,
    required this.startDate,
    required this.status,
    required this.title,
    required this.city,
    required this.countryCode,
    required this.createdAt,
    required this.equipment,
    required this.notes,
    required this.postalCode,
    required this.siteName,
    required this.street,
    required this.visitTemplates,
    this.endDate,
    this.resolutionHours,
    this.responseHours,
    this.contactId,
    this.contactName,
  });
  
  factory ContractDetail.fromJson(Map<String, Object?> json) => _$ContractDetailFromJson(json);
  
  @JsonKey(name: 'auto_renew')
  final bool autoRenew;
  @JsonKey(name: 'customer_id')
  final String customerId;
  @JsonKey(name: 'customer_name')
  final String customerName;
  @JsonKey(includeIfNull: false,name: 'end_date')
  final DateTime? endDate;
  final String id;
  final String number;

  /// Generated jobs that are not finished.
  @JsonKey(name: 'open_jobs')
  final int openJobs;
  @JsonKey(includeIfNull: false,name: 'resolution_hours')
  final int? resolutionHours;
  @JsonKey(includeIfNull: false,name: 'response_hours')
  final int? responseHours;
  @JsonKey(name: 'start_date')
  final DateTime startDate;

  /// draft | active | suspended | ended
  final String status;
  final String title;
  final String city;
  @JsonKey(includeIfNull: false,name: 'contact_id')
  final String? contactId;
  @JsonKey(includeIfNull: false,name: 'contact_name')
  final String? contactName;
  @JsonKey(name: 'country_code')
  final String countryCode;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  final List<JobEquipment> equipment;
  final String notes;
  @JsonKey(name: 'postal_code')
  final String postalCode;
  @JsonKey(name: 'site_name')
  final String siteName;
  final String street;
  @JsonKey(name: 'visit_templates')
  final List<VisitTemplate> visitTemplates;

  Map<String, Object?> toJson() => _$ContractDetailToJson(this);
}
