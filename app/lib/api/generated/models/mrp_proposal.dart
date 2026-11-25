// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'mrp_peg.dart';

part 'mrp_proposal.g.dart';

/// A proposal to buy or build.
@JsonSerializable()
class MrpProposal {
  const MrpProposal({
    required this.id,
    required this.kind,
    required this.lateValue,
    required this.needDate,
    required this.orderDate,
    required this.pegging,
    required this.productCode,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.reason,
    required this.runId,
    required this.runNumber,
    required this.status,
    this.convertedAt,
    this.convertedTo,
    this.supplierId,
    this.supplierName,
  });
  
  factory MrpProposal.fromJson(Map<String, Object?> json) => _$MrpProposalFromJson(json);
  
  @JsonKey(includeIfNull: false,name: 'converted_at')
  final DateTime? convertedAt;

  /// The purchase order or production order made from it.
  @JsonKey(includeIfNull: false,name: 'converted_to')
  final String? convertedTo;
  final String id;

  /// `purchase` or `production`.
  final String kind;

  /// The lead time reaches past the need date: the goods will be late.
  /// The name has been replaced because it contains a keyword. Original name: `late`.
  @JsonKey(name: 'late')
  final bool lateValue;

  /// When the stock is needed.
  @JsonKey(name: 'need_date')
  final DateTime needDate;

  /// When to order, or to start the build.
  @JsonKey(name: 'order_date')
  final DateTime orderDate;

  /// What the quantity is for.
  final List<MrpPeg> pegging;
  @JsonKey(name: 'product_code')
  final String productCode;
  @JsonKey(name: 'product_id')
  final String productId;
  @JsonKey(name: 'product_name')
  final String productName;
  final String quantity;

  /// `demand` (a requirement is not covered) or `safety_stock`.
  final String reason;
  @JsonKey(name: 'run_id')
  final String runId;
  @JsonKey(name: 'run_number')
  final String runNumber;

  /// `open`, `converted`, `dismissed` or `superseded` (a later run replaced it).
  final String status;
  @JsonKey(includeIfNull: false,name: 'supplier_id')
  final String? supplierId;
  @JsonKey(includeIfNull: false,name: 'supplier_name')
  final String? supplierName;

  Map<String, Object?> toJson() => _$MrpProposalToJson(this);
}
