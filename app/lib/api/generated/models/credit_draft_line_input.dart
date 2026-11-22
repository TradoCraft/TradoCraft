// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'credit_draft_line_input.g.dart';

@JsonSerializable()
class CreditDraftLineInput {
  const CreditDraftLineInput({
    required this.invoiceLineId,
    required this.quantity,
    this.netTotal,
  });
  
  factory CreditDraftLineInput.fromJson(Map<String, Object?> json) => _$CreditDraftLineInputFromJson(json);
  
  @JsonKey(name: 'invoice_line_id')
  final String invoiceLineId;

  /// Optional refund below the line's remaining value, excluding VAT.
  @JsonKey(includeIfNull: false,name: 'net_total')
  final String? netTotal;

  /// Quantity in the original invoice line's unit.
  final String quantity;

  Map<String, Object?> toJson() => _$CreditDraftLineInputToJson(this);
}
