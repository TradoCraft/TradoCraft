// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'billing_document.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BillingDocument _$BillingDocumentFromJson(Map<String, dynamic> json) =>
    BillingDocument(
      customer: BillingParty.fromJson(json['customer'] as Map<String, dynamic>),
      document: BillingSummary.fromJson(
        json['document'] as Map<String, dynamic>,
      ),
      language: json['language'] as String,
      lines: (json['lines'] as List<dynamic>)
          .map((e) => BillingLine.fromJson(e as Map<String, dynamic>))
          .toList(),
      seller: BillingParty.fromJson(json['seller'] as Map<String, dynamic>),
      vatRegime: json['vat_regime'] as String,
      rebateProgress: json['rebate_progress'] == null
          ? null
          : RebateProgress.fromJson(
              json['rebate_progress'] as Map<String, dynamic>,
            ),
    );

Map<String, dynamic> _$BillingDocumentToJson(BillingDocument instance) =>
    <String, dynamic>{
      'customer': instance.customer,
      'document': instance.document,
      'language': instance.language,
      'lines': instance.lines,
      'rebate_progress': ?instance.rebateProgress,
      'seller': instance.seller,
      'vat_regime': instance.vatRegime,
    };
