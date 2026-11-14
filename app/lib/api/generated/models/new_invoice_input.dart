// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'invoice_line_input.dart';

part 'new_invoice_input.g.dart';

/// Payload to register a draft invoice.
@JsonSerializable()
class NewInvoiceInput {
  const NewInvoiceInput({
    required this.invoiceDate,
    required this.invoiceNumber,
    this.currency,
    this.dueDate,
    this.lines,
    this.notes,
    this.purchaseOrderId,
    this.supplierId,
  });
  
  factory NewInvoiceInput.fromJson(Map<String, Object?> json) => _$NewInvoiceInputFromJson(json);
  
  /// Currency; defaults to the order's (or the supplier's) and must equal the order's.
  @JsonKey(includeIfNull: false)
  final String? currency;

  /// Due date; default invoice date plus the supplier's payment terms.
  @JsonKey(includeIfNull: false,name: 'due_date')
  final DateTime? dueDate;

  /// Date on the invoice.
  @JsonKey(name: 'invoice_date')
  final DateTime invoiceDate;

  /// The supplier's invoice number.
  @JsonKey(name: 'invoice_number')
  final String invoiceNumber;

  /// Lines; optional when a purchase order is given.
  @JsonKey(includeIfNull: false)
  final List<InvoiceLineInput>? lines;

  /// Free notes.
  @JsonKey(includeIfNull: false)
  final String? notes;

  /// Purchase order to match against. Without `lines` the lines are prefilled from what was.
  /// received and not yet invoiced.
  @JsonKey(includeIfNull: false,name: 'purchase_order_id')
  final String? purchaseOrderId;

  /// Supplier; may be left out when a purchase order is given.
  @JsonKey(includeIfNull: false,name: 'supplier_id')
  final String? supplierId;

  Map<String, Object?> toJson() => _$NewInvoiceInputToJson(this);
}
