// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'update_supplier_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

UpdateSupplierInput _$UpdateSupplierInputFromJson(Map<String, dynamic> json) =>
    UpdateSupplierInput(
      active: json['active'] as bool?,
      code: json['code'] as String?,
      contactPerson: json['contact_person'] as String?,
      country: json['country'] as String?,
      currency: json['currency'] as String?,
      email: json['email'] as String?,
      language: json['language'] as String?,
      name: json['name'] as String?,
      notes: json['notes'] as String?,
      paymentTermsDays: (json['payment_terms_days'] as num?)?.toInt(),
      phone: json['phone'] as String?,
      taxId: json['tax_id'] as String?,
    );

Map<String, dynamic> _$UpdateSupplierInputToJson(
  UpdateSupplierInput instance,
) => <String, dynamic>{
  'active': ?instance.active,
  'code': ?instance.code,
  'contact_person': ?instance.contactPerson,
  'country': ?instance.country,
  'currency': ?instance.currency,
  'email': ?instance.email,
  'language': ?instance.language,
  'name': ?instance.name,
  'notes': ?instance.notes,
  'payment_terms_days': ?instance.paymentTermsDays,
  'phone': ?instance.phone,
  'tax_id': ?instance.taxId,
};
