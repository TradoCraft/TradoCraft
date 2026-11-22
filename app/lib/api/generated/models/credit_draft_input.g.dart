// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'credit_draft_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CreditDraftInput _$CreditDraftInputFromJson(Map<String, dynamic> json) =>
    CreditDraftInput(
      documentDate: DateTime.parse(json['document_date'] as String),
      invoiceId: json['invoice_id'] as String,
      lines: (json['lines'] as List<dynamic>)
          .map((e) => CreditDraftLineInput.fromJson(e as Map<String, dynamic>))
          .toList(),
      reason: json['reason'] as String,
      requestId: json['request_id'] as String?,
    );

Map<String, dynamic> _$CreditDraftInputToJson(CreditDraftInput instance) =>
    <String, dynamic>{
      'document_date': instance.documentDate.toIso8601String(),
      'invoice_id': instance.invoiceId,
      'lines': instance.lines,
      'reason': instance.reason,
      'request_id': ?instance.requestId,
    };
