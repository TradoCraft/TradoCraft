// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'contact_phone.g.dart';

@JsonSerializable()
class ContactPhone {
  const ContactPhone({
    required this.label,
    required this.normalized,
    required this.number,
  });
  
  factory ContactPhone.fromJson(Map<String, Object?> json) => _$ContactPhoneFromJson(json);
  
  /// work | mobile | direct | other
  final String label;

  /// Digits with country code, used for lookup.
  final String normalized;

  /// As entered.
  final String number;

  Map<String, Object?> toJson() => _$ContactPhoneToJson(this);
}
