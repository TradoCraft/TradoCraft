// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'billing_summary.g.dart';

@JsonSerializable()
class BillingSummary {
  const BillingSummary({
    required this.currency,
    required this.customerId,
    required this.customerName,
    required this.documentDate,
    required this.grossTotal,
    required this.id,
    required this.isLegacy,
    required this.kind,
    required this.netTotal,
    required this.reason,
    required this.status,
    required this.vatTotal,
    this.deliveryNoteId,
    this.dueDate,
    this.evidenceReference,
    this.number,
    this.postedAt,
    this.sourceInvoiceId,
    this.sourceInvoiceNumber,
  });
  
  factory BillingSummary.fromJson(Map<String, Object?> json) => _$BillingSummaryFromJson(json);
  
  final String currency;
  @JsonKey(name: 'customer_id')
  final String customerId;
  @JsonKey(name: 'customer_name')
  final String customerName;
  @JsonKey(includeIfNull: false,name: 'delivery_note_id')
  final String? deliveryNoteId;
  @JsonKey(name: 'document_date')
  final DateTime documentDate;
  @JsonKey(includeIfNull: false,name: 'due_date')
  final DateTime? dueDate;
  @JsonKey(includeIfNull: false,name: 'evidence_reference')
  final String? evidenceReference;
  @JsonKey(name: 'gross_total')
  final String grossTotal;
  final String id;
  @JsonKey(name: 'is_legacy')
  final bool isLegacy;
  final String kind;
  @JsonKey(name: 'net_total')
  final String netTotal;
  @JsonKey(includeIfNull: false)
  final String? number;
  @JsonKey(includeIfNull: false,name: 'posted_at')
  final DateTime? postedAt;
  final String reason;
  @JsonKey(includeIfNull: false,name: 'source_invoice_id')
  final String? sourceInvoiceId;
  @JsonKey(includeIfNull: false,name: 'source_invoice_number')
  final String? sourceInvoiceNumber;
  final String status;
  @JsonKey(name: 'vat_total')
  final String vatTotal;

  Map<String, Object?> toJson() => _$BillingSummaryToJson(this);
}
