// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'legacy_invoice_line_input.g.dart';

@JsonSerializable()
class LegacyInvoiceLineInput {
  const LegacyInvoiceLineInput({
    required this.description,
    required this.includedInTurnover,
    required this.netTotal,
    required this.productCode,
    required this.quantity,
    required this.unit,
    required this.vatRate,
    required this.vatTotal,
  });
  
  factory LegacyInvoiceLineInput.fromJson(Map<String, Object?> json) => _$LegacyInvoiceLineInputFromJson(json);
  
  final String description;
  @JsonKey(name: 'included_in_turnover')
  final bool includedInTurnover;
  @JsonKey(name: 'net_total')
  final String netTotal;
  @JsonKey(name: 'product_code')
  final String productCode;
  final String quantity;
  final String unit;
  @JsonKey(name: 'vat_rate')
  final String vatRate;
  @JsonKey(name: 'vat_total')
  final String vatTotal;

  Map<String, Object?> toJson() => _$LegacyInvoiceLineInputToJson(this);
}
