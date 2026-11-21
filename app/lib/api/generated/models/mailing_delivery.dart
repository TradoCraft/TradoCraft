// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'mailing_delivery.g.dart';

@JsonSerializable()
class MailingDelivery {
  const MailingDelivery({
    required this.confirmedAt,
    required this.customerName,
    required this.delivery,
    required this.documentId,
    required this.documentTitle,
    required this.email,
    required this.language,
    required this.mailingId,
    required this.pdf,
    required this.revision,
    required this.subject,
    this.deliveryError,
  });
  
  factory MailingDelivery.fromJson(Map<String, Object?> json) => _$MailingDeliveryFromJson(json);
  
  @JsonKey(name: 'confirmed_at')
  final DateTime confirmedAt;
  @JsonKey(name: 'customer_name')
  final String customerName;
  final String delivery;
  @JsonKey(includeIfNull: false,name: 'delivery_error')
  final String? deliveryError;
  @JsonKey(name: 'document_id')
  final String documentId;
  @JsonKey(name: 'document_title')
  final String documentTitle;
  final String email;
  final String language;
  @JsonKey(name: 'mailing_id')
  final String mailingId;
  final String pdf;
  final int revision;
  final String subject;

  Map<String, Object?> toJson() => _$MailingDeliveryToJson(this);
}
