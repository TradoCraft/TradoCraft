// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'legacy_invoice_line_input.dart';

part 'legacy_invoice_input.g.dart';

@JsonSerializable()
class LegacyInvoiceInput {
  const LegacyInvoiceInput({
    required this.currency,
    required this.customerId,
    required this.documentDate,
    required this.evidenceReference,
    required this.lines,
    required this.number,
    required this.vatRegime,
  });
  
  factory LegacyInvoiceInput.fromJson(Map<String, Object?> json) => _$LegacyInvoiceInputFromJson(json);
  
  final String currency;
  @JsonKey(name: 'customer_id')
  final String customerId;
  @JsonKey(name: 'document_date')
  final DateTime documentDate;

  /// Reference to the external evidence reviewed by the person registering the invoice.
  @JsonKey(name: 'evidence_reference')
  final String evidenceReference;
  final List<LegacyInvoiceLineInput> lines;
  final String number;
  @JsonKey(name: 'vat_regime')
  final String vatRegime;

  Map<String, Object?> toJson() => _$LegacyInvoiceInputToJson(this);
}
