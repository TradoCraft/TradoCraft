// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'credit_draft_line_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CreditDraftLineInput _$CreditDraftLineInputFromJson(
  Map<String, dynamic> json,
) => CreditDraftLineInput(
  invoiceLineId: json['invoice_line_id'] as String,
  quantity: json['quantity'] as String,
  netTotal: json['net_total'] as String?,
);

Map<String, dynamic> _$CreditDraftLineInputToJson(
  CreditDraftLineInput instance,
) => <String, dynamic>{
  'invoice_line_id': instance.invoiceLineId,
  'net_total': ?instance.netTotal,
  'quantity': instance.quantity,
};
