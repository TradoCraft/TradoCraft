// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'contract_summary.g.dart';

@JsonSerializable()
class ContractSummary {
  const ContractSummary({
    required this.autoRenew,
    required this.customerId,
    required this.customerName,
    required this.id,
    required this.number,
    required this.openJobs,
    required this.startDate,
    required this.status,
    required this.title,
    this.endDate,
    this.resolutionHours,
    this.responseHours,
  });
  
  factory ContractSummary.fromJson(Map<String, Object?> json) => _$ContractSummaryFromJson(json);
  
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

  Map<String, Object?> toJson() => _$ContractSummaryToJson(this);
}
