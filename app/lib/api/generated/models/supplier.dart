// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'supplier.g.dart';

/// A supplier of the company.
@JsonSerializable()
class Supplier {
  const Supplier({
    required this.active,
    required this.code,
    required this.companyId,
    required this.contactPerson,
    required this.country,
    required this.createdAt,
    required this.currency,
    required this.email,
    required this.id,
    required this.name,
    required this.notes,
    required this.paymentTermsDays,
    required this.phone,
    required this.taxId,
    required this.updatedAt,
  });
  
  factory Supplier.fromJson(Map<String, Object?> json) => _$SupplierFromJson(json);
  
  final bool active;
  final String code;
  @JsonKey(name: 'company_id')
  final String companyId;
  @JsonKey(name: 'contact_person')
  final String contactPerson;
  final String country;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  final String currency;
  final String email;
  final String id;
  final String name;
  final String notes;
  @JsonKey(name: 'payment_terms_days')
  final int paymentTermsDays;
  final String phone;
  @JsonKey(name: 'tax_id')
  final String taxId;
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  Map<String, Object?> toJson() => _$SupplierToJson(this);
}
