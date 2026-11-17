// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'order.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Order _$OrderFromJson(Map<String, dynamic> json) => Order(
  cancelReason: json['cancel_reason'] as String,
  confirmationNote: json['confirmation_note'] as String,
  createdAt: DateTime.parse(json['created_at'] as String),
  lines: (json['lines'] as List<dynamic>)
      .map((e) => OrderLine.fromJson(e as Map<String, dynamic>))
      .toList(),
  notes: json['notes'] as String,
  order: OrderSummary.fromJson(json['order'] as Map<String, dynamic>),
  revision: (json['revision'] as num).toInt(),
  revisionStatus: json['revision_status'] as String,
  revisions: (json['revisions'] as List<dynamic>)
      .map((e) => OrderRevisionInfo.fromJson(e as Map<String, dynamic>))
      .toList(),
  suggestions: (json['suggestions'] as List<dynamic>)
      .map((e) => SalesSuggestion.fromJson(e as Map<String, dynamic>))
      .toList(),
  vatTotal: json['vat_total'] as String,
  warnings: (json['warnings'] as List<dynamic>)
      .map((e) => SalesWarning.fromJson(e as Map<String, dynamic>))
      .toList(),
  confirmedAt: json['confirmed_at'] == null
      ? null
      : DateTime.parse(json['confirmed_at'] as String),
  confirmedBy: json['confirmed_by'] as String?,
  confirmedRevision: (json['confirmed_revision'] as num?)?.toInt(),
  confirmedVia: json['confirmed_via'] as String?,
  version: (json['version'] as num?)?.toInt(),
);

Map<String, dynamic> _$OrderToJson(Order instance) => <String, dynamic>{
  'cancel_reason': instance.cancelReason,
  'confirmation_note': instance.confirmationNote,
  'confirmed_at': ?instance.confirmedAt?.toIso8601String(),
  'confirmed_by': ?instance.confirmedBy,
  'confirmed_revision': ?instance.confirmedRevision,
  'confirmed_via': ?instance.confirmedVia,
  'created_at': instance.createdAt.toIso8601String(),
  'lines': instance.lines,
  'notes': instance.notes,
  'order': instance.order,
  'revision': instance.revision,
  'revision_status': instance.revisionStatus,
  'revisions': instance.revisions,
  'suggestions': instance.suggestions,
  'vat_total': instance.vatTotal,
  'version': ?instance.version,
  'warnings': instance.warnings,
};
