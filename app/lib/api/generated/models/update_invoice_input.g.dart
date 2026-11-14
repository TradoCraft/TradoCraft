// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'update_invoice_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

UpdateInvoiceInput _$UpdateInvoiceInputFromJson(Map<String, dynamic> json) =>
    UpdateInvoiceInput(
      dueDate: json['due_date'] == null
          ? null
          : DateTime.parse(json['due_date'] as String),
      invoiceDate: json['invoice_date'] == null
          ? null
          : DateTime.parse(json['invoice_date'] as String),
      invoiceNumber: json['invoice_number'] as String?,
      lines: (json['lines'] as List<dynamic>?)
          ?.map((e) => InvoiceLineInput.fromJson(e as Map<String, dynamic>))
          .toList(),
      notes: json['notes'] as String?,
    );

Map<String, dynamic> _$UpdateInvoiceInputToJson(UpdateInvoiceInput instance) =>
    <String, dynamic>{
      'due_date': ?instance.dueDate?.toIso8601String(),
      'invoice_date': ?instance.invoiceDate?.toIso8601String(),
      'invoice_number': ?instance.invoiceNumber,
      'lines': ?instance.lines,
      'notes': ?instance.notes,
    };
