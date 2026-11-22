// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'invoice_draft_line_input.dart';

part 'invoice_draft_input.g.dart';

@JsonSerializable()
class InvoiceDraftInput {
  const InvoiceDraftInput({
    required this.deliveryNoteId,
    required this.documentDate,
    required this.lines,
    this.requestId,
  });
  
  factory InvoiceDraftInput.fromJson(Map<String, Object?> json) => _$InvoiceDraftInputFromJson(json);
  
  @JsonKey(name: 'delivery_note_id')
  final String deliveryNoteId;
  @JsonKey(name: 'document_date')
  final DateTime documentDate;
  final List<InvoiceDraftLineInput> lines;
  @JsonKey(includeIfNull: false,name: 'request_id')
  final String? requestId;

  Map<String, Object?> toJson() => _$InvoiceDraftInputToJson(this);
}
