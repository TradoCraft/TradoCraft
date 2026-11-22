// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'credit_draft_line_input.dart';

part 'credit_draft_input.g.dart';

@JsonSerializable()
class CreditDraftInput {
  const CreditDraftInput({
    required this.documentDate,
    required this.invoiceId,
    required this.lines,
    required this.reason,
    this.requestId,
  });
  
  factory CreditDraftInput.fromJson(Map<String, Object?> json) => _$CreditDraftInputFromJson(json);
  
  @JsonKey(name: 'document_date')
  final DateTime documentDate;
  @JsonKey(name: 'invoice_id')
  final String invoiceId;
  final List<CreditDraftLineInput> lines;
  final String reason;
  @JsonKey(includeIfNull: false,name: 'request_id')
  final String? requestId;

  Map<String, Object?> toJson() => _$CreditDraftInputToJson(this);
}
