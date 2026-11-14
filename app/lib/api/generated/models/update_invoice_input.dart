// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'invoice_line_input.dart';

part 'update_invoice_input.g.dart';

/// Payload to change a draft invoice; omitted fields keep their value.
@JsonSerializable()
class UpdateInvoiceInput {
  const UpdateInvoiceInput({
    this.dueDate,
    this.invoiceDate,
    this.invoiceNumber,
    this.lines,
    this.notes,
  });
  
  factory UpdateInvoiceInput.fromJson(Map<String, Object?> json) => _$UpdateInvoiceInputFromJson(json);
  
  /// New due date.
  @JsonKey(includeIfNull: false,name: 'due_date')
  final DateTime? dueDate;

  /// New invoice date.
  @JsonKey(includeIfNull: false,name: 'invoice_date')
  final DateTime? invoiceDate;

  /// New supplier invoice number.
  @JsonKey(includeIfNull: false,name: 'invoice_number')
  final String? invoiceNumber;

  /// Replaces all lines when present.
  @JsonKey(includeIfNull: false)
  final List<InvoiceLineInput>? lines;

  /// New notes.
  @JsonKey(includeIfNull: false)
  final String? notes;

  Map<String, Object?> toJson() => _$UpdateInvoiceInputToJson(this);
}
