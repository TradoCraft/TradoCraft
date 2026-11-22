// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'invoice_draft_line_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

InvoiceDraftLineInput _$InvoiceDraftLineInputFromJson(
  Map<String, dynamic> json,
) => InvoiceDraftLineInput(
  deliveryLineId: json['delivery_line_id'] as String,
  quantity: json['quantity'] as String,
);

Map<String, dynamic> _$InvoiceDraftLineInputToJson(
  InvoiceDraftLineInput instance,
) => <String, dynamic>{
  'delivery_line_id': instance.deliveryLineId,
  'quantity': instance.quantity,
};
