// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mark_paid_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MarkPaidInput _$MarkPaidInputFromJson(Map<String, dynamic> json) =>
    MarkPaidInput(
      paidAt: json['paid_at'] == null
          ? null
          : DateTime.parse(json['paid_at'] as String),
      paymentReference: json['payment_reference'] as String?,
    );

Map<String, dynamic> _$MarkPaidInputToJson(MarkPaidInput instance) =>
    <String, dynamic>{
      'paid_at': ?instance.paidAt?.toIso8601String(),
      'payment_reference': ?instance.paymentReference,
    };
