// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'package.g.dart';

@JsonSerializable()
class Package {
  const Package({
    required this.carrier,
    required this.condition,
    required this.conditionNote,
    required this.createdAt,
    required this.customerReference,
    required this.id,
    required this.notes,
    required this.number,
    required this.parcelCount,
    required this.photoCount,
    required this.receivedAt,
    required this.receivedBy,
    required this.receivedByName,
    required this.repairCount,
    required this.senderName,
    required this.status,
    required this.trackingNumber,
    required this.updatedAt,
    this.customerId,
    this.customerName,
    this.kind,
    this.openedAt,
    this.openedBy,
    this.openedByName,
  });
  
  factory Package.fromJson(Map<String, Object?> json) => _$PackageFromJson(json);
  
  final String carrier;

  /// intact | damaged | opened | wet
  final String condition;
  @JsonKey(name: 'condition_note')
  final String conditionNote;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;

  /// The sender, when known. Resolved at triage if the label only had a name.
  @JsonKey(includeIfNull: false,name: 'customer_id')
  final String? customerId;
  @JsonKey(includeIfNull: false,name: 'customer_name')
  final String? customerName;

  /// The customer's RMA number or the reference on their slip.
  @JsonKey(name: 'customer_reference')
  final String customerReference;
  final String id;

  /// What it turned out to be: repair | other | return_to_sender. Empty until opened.
  @JsonKey(includeIfNull: false)
  final String? kind;
  final String notes;

  /// PK-2027-00001
  final String number;
  @JsonKey(includeIfNull: false,name: 'opened_at')
  final DateTime? openedAt;
  @JsonKey(includeIfNull: false,name: 'opened_by')
  final String? openedBy;
  @JsonKey(includeIfNull: false,name: 'opened_by_name')
  final String? openedByName;
  @JsonKey(name: 'parcel_count')
  final int parcelCount;
  @JsonKey(name: 'photo_count')
  final int photoCount;
  @JsonKey(name: 'received_at')
  final DateTime receivedAt;
  @JsonKey(name: 'received_by')
  final String receivedBy;
  @JsonKey(name: 'received_by_name')
  final String receivedByName;

  /// How many repairs are linked to this parcel.
  @JsonKey(name: 'repair_count')
  final int repairCount;

  /// The sender as written on the label.
  @JsonKey(name: 'sender_name')
  final String senderName;

  /// registered | opened | linked | closed
  final String status;
  @JsonKey(name: 'tracking_number')
  final String trackingNumber;
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  Map<String, Object?> toJson() => _$PackageToJson(this);
}
