// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'customer.dart';

part 'customer_page.g.dart';

@JsonSerializable()
class CustomerPage {
  const CustomerPage({
    required this.items,
    required this.total,
  });
  
  factory CustomerPage.fromJson(Map<String, Object?> json) => _$CustomerPageFromJson(json);
  
  final List<Customer> items;
  final int total;

  Map<String, Object?> toJson() => _$CustomerPageToJson(this);
}
