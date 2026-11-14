// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'shipping_quote_input.g.dart';

@JsonSerializable()
class ShippingQuoteInput {
  const ShippingQuoteInput({
    required this.amount,
    this.carrier,
    this.currency,
    this.notes,
  });
  
  factory ShippingQuoteInput.fromJson(Map<String, Object?> json) => _$ShippingQuoteInputFromJson(json);
  
  final String amount;

  /// Carrier chosen; keeps the one entered when marking the request as requested.
  @JsonKey(includeIfNull: false)
  final String? carrier;

  /// Must equal the quotation currency. Defaults to it.
  @JsonKey(includeIfNull: false)
  final String? currency;
  @JsonKey(includeIfNull: false)
  final String? notes;

  Map<String, Object?> toJson() => _$ShippingQuoteInputToJson(this);
}
