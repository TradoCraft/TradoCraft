// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'billing_line.dart';
import 'billing_party.dart';
import 'billing_summary.dart';
import 'rebate_progress.dart';

part 'billing_document.g.dart';

@JsonSerializable()
class BillingDocument {
  const BillingDocument({
    required this.customer,
    required this.document,
    required this.language,
    required this.lines,
    required this.seller,
    required this.vatRegime,
    this.rebateProgress,
  });
  
  factory BillingDocument.fromJson(Map<String, Object?> json) => _$BillingDocumentFromJson(json);
  
  final BillingParty customer;
  final BillingSummary document;
  final String language;
  final List<BillingLine> lines;
  @JsonKey(includeIfNull: false,name: 'rebate_progress')
  final RebateProgress? rebateProgress;
  final BillingParty seller;
  @JsonKey(name: 'vat_regime')
  final String vatRegime;

  Map<String, Object?> toJson() => _$BillingDocumentToJson(this);
}
