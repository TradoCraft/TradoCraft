// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'new_supplier_input.g.dart';

/// Payload to create a supplier.
@JsonSerializable()
class NewSupplierInput {
  const NewSupplierInput({
    required this.country,
    required this.name,
    this.code,
    this.contactPerson,
    this.currency,
    this.email,
    this.notes,
    this.paymentTermsDays,
    this.phone,
    this.taxId,
  });
  
  factory NewSupplierInput.fromJson(Map<String, Object?> json) => _$NewSupplierInputFromJson(json);
  
  @JsonKey(includeIfNull: false)
  final String? code;
  @JsonKey(includeIfNull: false,name: 'contact_person')
  final String? contactPerson;
  final String country;
  @JsonKey(includeIfNull: false)
  final String? currency;
  @JsonKey(includeIfNull: false)
  final String? email;
  final String name;
  @JsonKey(includeIfNull: false)
  final String? notes;
  @JsonKey(includeIfNull: false,name: 'payment_terms_days')
  final int? paymentTermsDays;
  @JsonKey(includeIfNull: false)
  final String? phone;
  @JsonKey(includeIfNull: false,name: 'tax_id')
  final String? taxId;

  Map<String, Object?> toJson() => _$NewSupplierInputToJson(this);
}
