// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'portal_order.g.dart';

@JsonSerializable()
class PortalOrder {
  const PortalOrder({
    required this.canConfirm,
    required this.currency,
    required this.customerReference,
    required this.id,
    required this.number,
    required this.openPriorityRequests,
    required this.orderDate,
    required this.revision,
    required this.status,
    required this.subtotal,
    required this.total,
    required this.vatTotal,
    this.confirmedAt,
  });
  
  factory PortalOrder.fromJson(Map<String, Object?> json) => _$PortalOrderFromJson(json);
  
  /// True while this revision is the latest and waits for the customer's confirmation.
  @JsonKey(name: 'can_confirm')
  final bool canConfirm;
  @JsonKey(includeIfNull: false,name: 'confirmed_at')
  final DateTime? confirmedAt;
  final String currency;
  @JsonKey(name: 'customer_reference')
  final String customerReference;
  final String id;
  final String number;
  @JsonKey(name: 'open_priority_requests')
  final int openPriorityRequests;
  @JsonKey(name: 'order_date')
  final DateTime orderDate;

  /// The revision shown here: the latest that was sent or confirmed, never a draft.
  final int revision;

  /// sent | confirmed | cancelled
  final String status;
  final String subtotal;
  final String total;
  @JsonKey(name: 'vat_total')
  final String vatTotal;

  Map<String, Object?> toJson() => _$PortalOrderToJson(this);
}
