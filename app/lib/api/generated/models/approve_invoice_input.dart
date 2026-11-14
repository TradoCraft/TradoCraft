// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'approve_invoice_input.g.dart';

/// Payload to approve an invoice.
@JsonSerializable()
class ApproveInvoiceInput {
  const ApproveInvoiceInput({
    this.overrideReason,
  });
  
  factory ApproveInvoiceInput.fromJson(Map<String, Object?> json) => _$ApproveInvoiceInputFromJson(json);
  
  /// Required to approve an invoice whose match is not clean; recorded and audited.
  @JsonKey(includeIfNull: false,name: 'override_reason')
  final String? overrideReason;

  Map<String, Object?> toJson() => _$ApproveInvoiceInputToJson(this);
}
