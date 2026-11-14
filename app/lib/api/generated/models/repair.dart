// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'repair.g.dart';

@JsonSerializable()
class Repair {
  const Repair({
    required this.createdAt,
    required this.customerId,
    required this.customerName,
    required this.customerReference,
    required this.diagnosis,
    required this.faultDescription,
    required this.findings,
    required this.id,
    required this.number,
    required this.photoCount,
    required this.priority,
    required this.productDescription,
    required this.serialNumber,
    required this.source,
    required this.status,
    required this.updatedAt,
    required this.warranty,
    required this.warrantyAuto,
    required this.warrantyOverridden,
    this.assignedName,
    this.assignedUserId,
    this.completedAt,
    this.contactId,
    this.contactName,
    this.departmentId,
    this.departmentName,
    this.productCode,
    this.productId,
    this.receivedAt,
    this.serialUnitId,
    this.ticketId,
    this.ticketNumber,
  });
  
  factory Repair.fromJson(Map<String, Object?> json) => _$RepairFromJson(json);
  
  @JsonKey(includeIfNull: false,name: 'assigned_name')
  final String? assignedName;
  @JsonKey(includeIfNull: false,name: 'assigned_user_id')
  final String? assignedUserId;
  @JsonKey(includeIfNull: false,name: 'completed_at')
  final DateTime? completedAt;
  @JsonKey(includeIfNull: false,name: 'contact_id')
  final String? contactId;
  @JsonKey(includeIfNull: false,name: 'contact_name')
  final String? contactName;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @JsonKey(name: 'customer_id')
  final String customerId;
  @JsonKey(name: 'customer_name')
  final String customerName;
  @JsonKey(name: 'customer_reference')
  final String customerReference;
  @JsonKey(includeIfNull: false,name: 'department_id')
  final String? departmentId;
  @JsonKey(includeIfNull: false,name: 'department_name')
  final String? departmentName;

  /// The department's conclusion.
  final String diagnosis;
  @JsonKey(name: 'fault_description')
  final String faultDescription;

  /// What was found when the product was looked at.
  final String findings;
  final String id;
  final String number;
  @JsonKey(name: 'photo_count')
  final int photoCount;
  final String priority;
  @JsonKey(includeIfNull: false,name: 'product_code')
  final String? productCode;

  /// The product as the customer describes it.
  @JsonKey(name: 'product_description')
  final String productDescription;
  @JsonKey(includeIfNull: false,name: 'product_id')
  final String? productId;
  @JsonKey(includeIfNull: false,name: 'received_at')
  final DateTime? receivedAt;
  @JsonKey(name: 'serial_number')
  final String serialNumber;

  /// The serial unit (engineering) the warranty was looked up from.
  @JsonKey(includeIfNull: false,name: 'serial_unit_id')
  final String? serialUnitId;

  /// staff | portal | package
  final String source;

  /// announced | received | routed | in_progress | waiting_customer | waiting_parts | completed | shipped | cancelled
  final String status;

  /// The ticket where the repair was announced or discussed.
  @JsonKey(includeIfNull: false,name: 'ticket_id')
  final String? ticketId;
  @JsonKey(includeIfNull: false,name: 'ticket_number')
  final String? ticketNumber;
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  /// The final warranty status: unknown | in_warranty | out_of_warranty | void. See `/repairs/{id}/warranty`.
  /// for the automatic result and the override behind it.
  final String warranty;

  /// The automatic result of the lookup: unknown | in_warranty | out_of_warranty
  @JsonKey(name: 'warranty_auto')
  final String warrantyAuto;

  /// True when the workshop declared the warranty void (misuse).
  @JsonKey(name: 'warranty_overridden')
  final bool warrantyOverridden;

  Map<String, Object?> toJson() => _$RepairToJson(this);
}
