// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'new_supplier_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

NewSupplierInput _$NewSupplierInputFromJson(Map<String, dynamic> json) =>
    NewSupplierInput(
      country: json['country'] as String,
      name: json['name'] as String,
      code: json['code'] as String?,
      contactPerson: json['contact_person'] as String?,
      currency: json['currency'] as String?,
      email: json['email'] as String?,
      language: json['language'] as String?,
      notes: json['notes'] as String?,
      paymentTermsDays: (json['payment_terms_days'] as num?)?.toInt(),
      phone: json['phone'] as String?,
      taxId: json['tax_id'] as String?,
    );

Map<String, dynamic> _$NewSupplierInputToJson(NewSupplierInput instance) =>
    <String, dynamic>{
      'code': ?instance.code,
      'contact_person': ?instance.contactPerson,
      'country': instance.country,
      'currency': ?instance.currency,
      'email': ?instance.email,
      'language': ?instance.language,
      'name': instance.name,
      'notes': ?instance.notes,
      'payment_terms_days': ?instance.paymentTermsDays,
      'phone': ?instance.phone,
      'tax_id': ?instance.taxId,
    };
