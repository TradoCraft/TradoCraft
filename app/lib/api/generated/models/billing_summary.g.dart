// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'billing_summary.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BillingSummary _$BillingSummaryFromJson(Map<String, dynamic> json) =>
    BillingSummary(
      currency: json['currency'] as String,
      customerId: json['customer_id'] as String,
      customerName: json['customer_name'] as String,
      documentDate: DateTime.parse(json['document_date'] as String),
      grossTotal: json['gross_total'] as String,
      id: json['id'] as String,
      isLegacy: json['is_legacy'] as bool,
      kind: json['kind'] as String,
      netTotal: json['net_total'] as String,
      reason: json['reason'] as String,
      status: json['status'] as String,
      vatTotal: json['vat_total'] as String,
      deliveryNoteId: json['delivery_note_id'] as String?,
      dueDate: json['due_date'] == null
          ? null
          : DateTime.parse(json['due_date'] as String),
      evidenceReference: json['evidence_reference'] as String?,
      number: json['number'] as String?,
      postedAt: json['posted_at'] == null
          ? null
          : DateTime.parse(json['posted_at'] as String),
      sourceInvoiceId: json['source_invoice_id'] as String?,
      sourceInvoiceNumber: json['source_invoice_number'] as String?,
    );

Map<String, dynamic> _$BillingSummaryToJson(BillingSummary instance) =>
    <String, dynamic>{
      'currency': instance.currency,
      'customer_id': instance.customerId,
      'customer_name': instance.customerName,
      'delivery_note_id': ?instance.deliveryNoteId,
      'document_date': instance.documentDate.toIso8601String(),
      'due_date': ?instance.dueDate?.toIso8601String(),
      'evidence_reference': ?instance.evidenceReference,
      'gross_total': instance.grossTotal,
      'id': instance.id,
      'is_legacy': instance.isLegacy,
      'kind': instance.kind,
      'net_total': instance.netTotal,
      'number': ?instance.number,
      'posted_at': ?instance.postedAt?.toIso8601String(),
      'reason': instance.reason,
      'source_invoice_id': ?instance.sourceInvoiceId,
      'source_invoice_number': ?instance.sourceInvoiceNumber,
      'status': instance.status,
      'vat_total': instance.vatTotal,
    };
