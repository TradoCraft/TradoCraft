// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mrp_proposal.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MrpProposal _$MrpProposalFromJson(Map<String, dynamic> json) => MrpProposal(
  id: json['id'] as String,
  kind: json['kind'] as String,
  lateValue: json['late'] as bool,
  needDate: DateTime.parse(json['need_date'] as String),
  orderDate: DateTime.parse(json['order_date'] as String),
  pegging: json['pegging'],
  productCode: json['product_code'] as String,
  productId: json['product_id'] as String,
  productName: json['product_name'] as String,
  quantity: json['quantity'] as String,
  reason: json['reason'] as String,
  runId: json['run_id'] as String,
  runNumber: json['run_number'] as String,
  status: json['status'] as String,
  convertedAt: json['converted_at'] == null
      ? null
      : DateTime.parse(json['converted_at'] as String),
  convertedTo: json['converted_to'] as String?,
  supplierId: json['supplier_id'] as String?,
  supplierName: json['supplier_name'] as String?,
);

Map<String, dynamic> _$MrpProposalToJson(MrpProposal instance) =>
    <String, dynamic>{
      'converted_at': ?instance.convertedAt?.toIso8601String(),
      'converted_to': ?instance.convertedTo,
      'id': instance.id,
      'kind': instance.kind,
      'late': instance.lateValue,
      'need_date': instance.needDate.toIso8601String(),
      'order_date': instance.orderDate.toIso8601String(),
      'pegging': instance.pegging,
      'product_code': instance.productCode,
      'product_id': instance.productId,
      'product_name': instance.productName,
      'quantity': instance.quantity,
      'reason': instance.reason,
      'run_id': instance.runId,
      'run_number': instance.runNumber,
      'status': instance.status,
      'supplier_id': ?instance.supplierId,
      'supplier_name': ?instance.supplierName,
    };
