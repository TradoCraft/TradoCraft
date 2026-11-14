// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'contact.dart';
import 'customer_match.dart';

part 'lookup_result.g.dart';

@JsonSerializable()
class LookupResult {
  const LookupResult({
    required this.contacts,
    required this.customers,
  });
  
  factory LookupResult.fromJson(Map<String, Object?> json) => _$LookupResultFromJson(json);
  
  final List<Contact> contacts;

  /// Customers whose main phone number or e-mail address matches. Useful when the caller is.
  /// not (yet) a known contact, or calls from the customer's switchboard.
  final List<CustomerMatch> customers;

  Map<String, Object?> toJson() => _$LookupResultToJson(this);
}
