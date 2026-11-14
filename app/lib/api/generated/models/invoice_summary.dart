// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'invoice_summary.g.dart';

/// A supplier invoice header.
@JsonSerializable()
class InvoiceSummary {
  const InvoiceSummary({
    required this.companyId,
    required this.createdAt,
    required this.createdByUserId,
    required this.currency,
    required this.disputeReason,
    required this.dueDate,
    required this.grossTotal,
    required this.id,
    required this.invoiceDate,
    required this.invoiceNumber,
    required this.netTotal,
    required this.notes,
    required this.number,
    required this.overrideReason,
    required this.paymentReference,
    required this.status,
    required this.supplierId,
    required this.supplierName,
    required this.updatedAt,
    required this.vatTotal,
    this.approvedAt,
    this.approvedByUserId,
    this.paidAt,
    this.purchaseOrderId,
    this.purchaseOrderNumber,
  });
  
  factory InvoiceSummary.fromJson(Map<String, Object?> json) => _$InvoiceSummaryFromJson(json);
  
  /// When it was approved.
  @JsonKey(includeIfNull: false,name: 'approved_at')
  final DateTime? approvedAt;

  /// Who approved it.
  @JsonKey(includeIfNull: false,name: 'approved_by_user_id')
  final String? approvedByUserId;

  /// Owning company.
  @JsonKey(name: 'company_id')
  final String companyId;

  /// Creation time.
  @JsonKey(name: 'created_at')
  final DateTime createdAt;

  /// Who registered the invoice.
  @JsonKey(name: 'created_by_user_id')
  final String createdByUserId;

  /// Currency; equals the purchase order's currency when there is one.
  final String currency;

  /// Why the invoice was disputed (while disputed).
  @JsonKey(name: 'dispute_reason')
  final String disputeReason;

  /// Payment due date (default: invoice date plus the supplier's payment terms).
  @JsonKey(name: 'due_date')
  final DateTime dueDate;

  /// Net plus VAT.
  @JsonKey(name: 'gross_total')
  final String grossTotal;

  /// Invoice id.
  final String id;

  /// Date on the invoice.
  @JsonKey(name: 'invoice_date')
  final DateTime invoiceDate;

  /// The supplier's own invoice number; unique per supplier.
  @JsonKey(name: 'invoice_number')
  final String invoiceNumber;

  /// Sum of the line net amounts.
  @JsonKey(name: 'net_total')
  final String netTotal;

  /// Free notes.
  final String notes;

  /// Internal document number, e.g. `SI2027-00001`.
  final String number;

  /// Reason given when the invoice was approved against a failed match.
  @JsonKey(name: 'override_reason')
  final String overrideReason;

  /// Payment date, once paid.
  @JsonKey(includeIfNull: false,name: 'paid_at')
  final DateTime? paidAt;

  /// Bank or payment reference, once paid.
  @JsonKey(name: 'payment_reference')
  final String paymentReference;

  /// The purchase order the invoice is matched against, if any.
  @JsonKey(includeIfNull: false,name: 'purchase_order_id')
  final String? purchaseOrderId;

  /// Number of that purchase order, read through purchasing.
  @JsonKey(includeIfNull: false,name: 'purchase_order_number')
  final String? purchaseOrderNumber;

  /// draft | matched | disputed | approved | paid
  final String status;

  /// Supplier (purchasing).
  @JsonKey(name: 'supplier_id')
  final String supplierId;

  /// Supplier name, read through purchasing.
  @JsonKey(name: 'supplier_name')
  final String supplierName;

  /// Last change.
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  /// Sum of the line VAT amounts.
  @JsonKey(name: 'vat_total')
  final String vatTotal;

  Map<String, Object?> toJson() => _$InvoiceSummaryToJson(this);
}
