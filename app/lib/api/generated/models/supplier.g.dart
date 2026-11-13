// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'supplier.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Supplier _$SupplierFromJson(Map<String, dynamic> json) => Supplier(
  active: json['active'] as bool,
  code: json['code'] as String,
  companyId: json['company_id'] as String,
  contactPerson: json['contact_person'] as String,
  country: json['country'] as String,
  createdAt: DateTime.parse(json['created_at'] as String),
  currency: json['currency'] as String,
  email: json['email'] as String,
  id: json['id'] as String,
  language: json['language'] as String,
  name: json['name'] as String,
  notes: json['notes'] as String,
  paymentTermsDays: (json['payment_terms_days'] as num).toInt(),
  phone: json['phone'] as String,
  taxId: json['tax_id'] as String,
  updatedAt: DateTime.parse(json['updated_at'] as String),
);

Map<String, dynamic> _$SupplierToJson(Supplier instance) => <String, dynamic>{
  'active': instance.active,
  'code': instance.code,
  'company_id': instance.companyId,
  'contact_person': instance.contactPerson,
  'country': instance.country,
  'created_at': instance.createdAt.toIso8601String(),
  'currency': instance.currency,
  'email': instance.email,
  'id': instance.id,
  'language': instance.language,
  'name': instance.name,
  'notes': instance.notes,
  'payment_terms_days': instance.paymentTermsDays,
  'phone': instance.phone,
  'tax_id': instance.taxId,
  'updated_at': instance.updatedAt.toIso8601String(),
};
