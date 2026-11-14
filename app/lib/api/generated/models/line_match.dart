// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'line_status.dart';

part 'line_match.g.dart';

/// Evaluated line: the status and the numbers behind it.
@JsonSerializable()
class LineMatch {
  const LineMatch({
    required this.invoiceLineId,
    required this.invoiceUnitPrice,
    required this.issues,
    required this.lineQuantity,
    required this.status,
    this.invoicedQuantity,
    this.orderedQuantity,
    this.poUnitPrice,
    this.priceVariancePct,
    this.receivedQuantity,
  });
  
  factory LineMatch.fromJson(Map<String, Object?> json) => _$LineMatchFromJson(json);
  
  /// The invoice line (set by the caller; nil in pure unit tests).
  @JsonKey(name: 'invoice_line_id')
  final String invoiceLineId;

  /// Unit price on this line.
  @JsonKey(name: 'invoice_unit_price')
  final String invoiceUnitPrice;

  /// Quantity invoiced on the order line in total (this line and all others counted).
  @JsonKey(includeIfNull: false,name: 'invoiced_quantity')
  final String? invoicedQuantity;

  /// Every problem found on the line; empty when ok.
  final List<LineStatus> issues;

  /// Quantity on this line.
  @JsonKey(name: 'line_quantity')
  final String lineQuantity;

  /// Ordered quantity, if the line points at an order line.
  @JsonKey(includeIfNull: false,name: 'ordered_quantity')
  final String? orderedQuantity;

  /// Unit price on the order line.
  @JsonKey(includeIfNull: false,name: 'po_unit_price')
  final String? poUnitPrice;

  /// Invoice price minus order price as a percentage of the order price (a zero order price.
  /// and a different invoice price gives 100).
  @JsonKey(includeIfNull: false,name: 'price_variance_pct')
  final String? priceVariancePct;

  /// Received quantity, if the line points at an order line.
  @JsonKey(includeIfNull: false,name: 'received_quantity')
  final String? receivedQuantity;

  /// The first problem found (not_received, over_invoiced, price_variance), or ok.
  final LineStatus status;

  Map<String, Object?> toJson() => _$LineMatchToJson(this);
}
