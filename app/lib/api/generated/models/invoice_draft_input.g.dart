// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'invoice_draft_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

InvoiceDraftInput _$InvoiceDraftInputFromJson(Map<String, dynamic> json) =>
    InvoiceDraftInput(
      deliveryNoteId: json['delivery_note_id'] as String,
      documentDate: DateTime.parse(json['document_date'] as String),
      lines: (json['lines'] as List<dynamic>)
          .map((e) => InvoiceDraftLineInput.fromJson(e as Map<String, dynamic>))
          .toList(),
      requestId: json['request_id'] as String?,
    );

Map<String, dynamic> _$InvoiceDraftInputToJson(InvoiceDraftInput instance) =>
    <String, dynamic>{
      'delivery_note_id': instance.deliveryNoteId,
      'document_date': instance.documentDate.toIso8601String(),
      'lines': instance.lines,
      'request_id': ?instance.requestId,
    };
