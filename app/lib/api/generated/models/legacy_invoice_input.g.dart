// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'legacy_invoice_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LegacyInvoiceInput _$LegacyInvoiceInputFromJson(Map<String, dynamic> json) =>
    LegacyInvoiceInput(
      currency: json['currency'] as String,
      customerId: json['customer_id'] as String,
      documentDate: DateTime.parse(json['document_date'] as String),
      evidenceReference: json['evidence_reference'] as String,
      lines: (json['lines'] as List<dynamic>)
          .map(
            (e) => LegacyInvoiceLineInput.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
      number: json['number'] as String,
      vatRegime: json['vat_regime'] as String,
    );

Map<String, dynamic> _$LegacyInvoiceInputToJson(LegacyInvoiceInput instance) =>
    <String, dynamic>{
      'currency': instance.currency,
      'customer_id': instance.customerId,
      'document_date': instance.documentDate.toIso8601String(),
      'evidence_reference': instance.evidenceReference,
      'lines': instance.lines,
      'number': instance.number,
      'vat_regime': instance.vatRegime,
    };
