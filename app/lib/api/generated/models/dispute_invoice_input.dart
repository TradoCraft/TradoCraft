// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'dispute_invoice_input.g.dart';

/// Payload to dispute an invoice.
@JsonSerializable()
class DisputeInvoiceInput {
  const DisputeInvoiceInput({
    required this.reason,
  });
  
  factory DisputeInvoiceInput.fromJson(Map<String, Object?> json) => _$DisputeInvoiceInputFromJson(json);
  
  /// Why the invoice is disputed (required).
  final String reason;

  Map<String, Object?> toJson() => _$DisputeInvoiceInputToJson(this);
}
