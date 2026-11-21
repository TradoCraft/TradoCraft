// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mailing_delivery.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MailingDelivery _$MailingDeliveryFromJson(Map<String, dynamic> json) =>
    MailingDelivery(
      confirmedAt: DateTime.parse(json['confirmed_at'] as String),
      customerName: json['customer_name'] as String,
      delivery: json['delivery'] as String,
      documentId: json['document_id'] as String,
      documentTitle: json['document_title'] as String,
      email: json['email'] as String,
      language: json['language'] as String,
      mailingId: json['mailing_id'] as String,
      pdf: json['pdf'] as String,
      revision: (json['revision'] as num).toInt(),
      subject: json['subject'] as String,
      deliveryError: json['delivery_error'] as String?,
    );

Map<String, dynamic> _$MailingDeliveryToJson(MailingDelivery instance) =>
    <String, dynamic>{
      'confirmed_at': instance.confirmedAt.toIso8601String(),
      'customer_name': instance.customerName,
      'delivery': instance.delivery,
      'delivery_error': ?instance.deliveryError,
      'document_id': instance.documentId,
      'document_title': instance.documentTitle,
      'email': instance.email,
      'language': instance.language,
      'mailing_id': instance.mailingId,
      'pdf': instance.pdf,
      'revision': instance.revision,
      'subject': instance.subject,
    };
