// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'invoice_draft_line_input.g.dart';

@JsonSerializable()
class InvoiceDraftLineInput {
  const InvoiceDraftLineInput({
    required this.deliveryLineId,
    required this.quantity,
  });
  
  factory InvoiceDraftLineInput.fromJson(Map<String, Object?> json) => _$InvoiceDraftLineInputFromJson(json);
  
  @JsonKey(name: 'delivery_line_id')
  final String deliveryLineId;

  /// Quantity in the stock unit printed on the delivery note.
  final String quantity;

  Map<String, Object?> toJson() => _$InvoiceDraftLineInputToJson(this);
}
