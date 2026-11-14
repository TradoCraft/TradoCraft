// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'mark_paid_input.g.dart';

/// Payload to record a payment.
@JsonSerializable()
class MarkPaidInput {
  const MarkPaidInput({
    this.paidAt,
    this.paymentReference,
  });
  
  factory MarkPaidInput.fromJson(Map<String, Object?> json) => _$MarkPaidInputFromJson(json);
  
  /// Payment date, default today.
  @JsonKey(includeIfNull: false,name: 'paid_at')
  final DateTime? paidAt;

  /// Bank or payment reference.
  @JsonKey(includeIfNull: false,name: 'payment_reference')
  final String? paymentReference;

  Map<String, Object?> toJson() => _$MarkPaidInputToJson(this);
}
