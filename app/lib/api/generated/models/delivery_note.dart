// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'closure_warning.dart';
import 'delivery_note_line.dart';
import 'delivery_ship_to.dart';

part 'delivery_note.g.dart';

@JsonSerializable()
class DeliveryNote {
  const DeliveryNote({
    required this.carrier,
    required this.createdAt,
    required this.customerId,
    required this.customerName,
    required this.id,
    required this.lines,
    required this.notes,
    required this.number,
    required this.orderId,
    required this.orderNumber,
    required this.orderRevision,
    required this.plannedOnClosure,
    required this.shipTo,
    required this.status,
    required this.trackingNumber,
    required this.updatedAt,
    this.closureOverrideReason,
    this.closureWarning,
    this.plannedDate,
    this.shippedAt,
  });
  
  factory DeliveryNote.fromJson(Map<String, Object?> json) => _$DeliveryNoteFromJson(json);
  
  final String carrier;

  /// Why a delivery on a closure was allowed (policy `override`).
  @JsonKey(includeIfNull: false,name: 'closure_override_reason')
  final String? closureOverrideReason;

  /// Live: the customer is closed on the planned date of a planned note, also when the closure.
  /// was added after the date was set.
  @JsonKey(includeIfNull: false,name: 'closure_warning')
  final ClosureWarning? closureWarning;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  @JsonKey(name: 'customer_id')
  final String customerId;
  @JsonKey(name: 'customer_name')
  final String customerName;
  final String id;
  final List<DeliveryNoteLine> lines;
  final String notes;
  final String number;
  @JsonKey(name: 'order_id')
  final String orderId;
  @JsonKey(name: 'order_number')
  final String orderNumber;
  @JsonKey(name: 'order_revision')
  final int orderRevision;
  @JsonKey(includeIfNull: false,name: 'planned_date')
  final DateTime? plannedDate;

  /// The customer was closed on the planned date when it was saved.
  @JsonKey(name: 'planned_on_closure')
  final bool plannedOnClosure;
  @JsonKey(name: 'ship_to')
  final DeliveryShipTo shipTo;
  @JsonKey(includeIfNull: false,name: 'shipped_at')
  final DateTime? shippedAt;

  /// planned | shipped | cancelled
  final String status;
  @JsonKey(name: 'tracking_number')
  final String trackingNumber;

  /// Send it back as `expected_updated_at` when saving: a note someone else changed meanwhile is refused.
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  Map<String, Object?> toJson() => _$DeliveryNoteToJson(this);
}
