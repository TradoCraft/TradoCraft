// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'invoice_detail.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

InvoiceDetail _$InvoiceDetailFromJson(Map<String, dynamic> json) =>
    InvoiceDetail(
      companyId: json['company_id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      createdByUserId: json['created_by_user_id'] as String,
      currency: json['currency'] as String,
      disputeReason: json['dispute_reason'] as String,
      dueDate: DateTime.parse(json['due_date'] as String),
      grossTotal: json['gross_total'] as String,
      id: json['id'] as String,
      invoiceDate: DateTime.parse(json['invoice_date'] as String),
      invoiceNumber: json['invoice_number'] as String,
      netTotal: json['net_total'] as String,
      notes: json['notes'] as String,
      number: json['number'] as String,
      overrideReason: json['override_reason'] as String,
      paymentReference: json['payment_reference'] as String,
      status: json['status'] as String,
      supplierId: json['supplier_id'] as String,
      supplierName: json['supplier_name'] as String,
      updatedAt: DateTime.parse(json['updated_at'] as String),
      vatTotal: json['vat_total'] as String,
      lines: (json['lines'] as List<dynamic>)
          .map((e) => InvoiceLine.fromJson(e as Map<String, dynamic>))
          .toList(),
      matchReport: MatchReport.fromJson(
        json['match_report'] as Map<String, dynamic>,
      ),
      approvedAt: json['approved_at'] == null
          ? null
          : DateTime.parse(json['approved_at'] as String),
      approvedByUserId: json['approved_by_user_id'] as String?,
      paidAt: json['paid_at'] == null
          ? null
          : DateTime.parse(json['paid_at'] as String),
      purchaseOrderId: json['purchase_order_id'] as String?,
      purchaseOrderNumber: json['purchase_order_number'] as String?,
    );

Map<String, dynamic> _$InvoiceDetailToJson(InvoiceDetail instance) =>
    <String, dynamic>{
      'approved_at': ?instance.approvedAt?.toIso8601String(),
      'approved_by_user_id': ?instance.approvedByUserId,
      'company_id': instance.companyId,
      'created_at': instance.createdAt.toIso8601String(),
      'created_by_user_id': instance.createdByUserId,
      'currency': instance.currency,
      'dispute_reason': instance.disputeReason,
      'due_date': instance.dueDate.toIso8601String(),
      'gross_total': instance.grossTotal,
      'id': instance.id,
      'invoice_date': instance.invoiceDate.toIso8601String(),
      'invoice_number': instance.invoiceNumber,
      'net_total': instance.netTotal,
      'notes': instance.notes,
      'number': instance.number,
      'override_reason': instance.overrideReason,
      'paid_at': ?instance.paidAt?.toIso8601String(),
      'payment_reference': instance.paymentReference,
      'purchase_order_id': ?instance.purchaseOrderId,
      'purchase_order_number': ?instance.purchaseOrderNumber,
      'status': instance.status,
      'supplier_id': instance.supplierId,
      'supplier_name': instance.supplierName,
      'updated_at': instance.updatedAt.toIso8601String(),
      'vat_total': instance.vatTotal,
      'lines': instance.lines,
      'match_report': instance.matchReport,
    };
