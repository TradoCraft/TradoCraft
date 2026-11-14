// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'new_invoice_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

NewInvoiceInput _$NewInvoiceInputFromJson(Map<String, dynamic> json) =>
    NewInvoiceInput(
      invoiceDate: DateTime.parse(json['invoice_date'] as String),
      invoiceNumber: json['invoice_number'] as String,
      currency: json['currency'] as String?,
      dueDate: json['due_date'] == null
          ? null
          : DateTime.parse(json['due_date'] as String),
      lines: (json['lines'] as List<dynamic>?)
          ?.map((e) => InvoiceLineInput.fromJson(e as Map<String, dynamic>))
          .toList(),
      notes: json['notes'] as String?,
      purchaseOrderId: json['purchase_order_id'] as String?,
      supplierId: json['supplier_id'] as String?,
    );

Map<String, dynamic> _$NewInvoiceInputToJson(NewInvoiceInput instance) =>
    <String, dynamic>{
      'currency': ?instance.currency,
      'due_date': ?instance.dueDate?.toIso8601String(),
      'invoice_date': instance.invoiceDate.toIso8601String(),
      'invoice_number': instance.invoiceNumber,
      'lines': ?instance.lines,
      'notes': ?instance.notes,
      'purchase_order_id': ?instance.purchaseOrderId,
      'supplier_id': ?instance.supplierId,
    };
