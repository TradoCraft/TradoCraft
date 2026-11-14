// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'update_supplier_input.g.dart';

/// Partial supplier update; omitted fields keep their value.
@JsonSerializable()
class UpdateSupplierInput {
  const UpdateSupplierInput({
    this.active,
    this.code,
    this.contactPerson,
    this.country,
    this.currency,
    this.email,
    this.name,
    this.notes,
    this.paymentTermsDays,
    this.phone,
    this.taxId,
  });
  
  factory UpdateSupplierInput.fromJson(Map<String, Object?> json) => _$UpdateSupplierInputFromJson(json);
  
  @JsonKey(includeIfNull: false)
  final bool? active;
  @JsonKey(includeIfNull: false)
  final String? code;
  @JsonKey(includeIfNull: false,name: 'contact_person')
  final String? contactPerson;
  @JsonKey(includeIfNull: false)
  final String? country;
  @JsonKey(includeIfNull: false)
  final String? currency;
  @JsonKey(includeIfNull: false)
  final String? email;
  @JsonKey(includeIfNull: false)
  final String? name;
  @JsonKey(includeIfNull: false)
  final String? notes;
  @JsonKey(includeIfNull: false,name: 'payment_terms_days')
  final int? paymentTermsDays;
  @JsonKey(includeIfNull: false)
  final String? phone;
  @JsonKey(includeIfNull: false,name: 'tax_id')
  final String? taxId;

  Map<String, Object?> toJson() => _$UpdateSupplierInputToJson(this);
}
