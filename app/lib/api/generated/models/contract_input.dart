// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'template_input.dart';

part 'contract_input.g.dart';

@JsonSerializable()
class ContractInput {
  const ContractInput({
    required this.customerId,
    required this.startDate,
    required this.title,
    this.autoRenew,
    this.city,
    this.contactId,
    this.countryCode,
    this.endDate,
    this.equipmentIds,
    this.notes,
    this.postalCode,
    this.resolutionHours,
    this.responseHours,
    this.siteName,
    this.street,
    this.visitTemplates,
  });
  
  factory ContractInput.fromJson(Map<String, Object?> json) => _$ContractInputFromJson(json);
  
  @JsonKey(includeIfNull: false,name: 'auto_renew')
  final bool? autoRenew;
  @JsonKey(includeIfNull: false)
  final String? city;
  @JsonKey(includeIfNull: false,name: 'contact_id')
  final String? contactId;
  @JsonKey(includeIfNull: false,name: 'country_code')
  final String? countryCode;
  @JsonKey(name: 'customer_id')
  final String customerId;
  @JsonKey(includeIfNull: false,name: 'end_date')
  final DateTime? endDate;

  /// Units of the customer covered by the contract.
  @JsonKey(includeIfNull: false,name: 'equipment_ids')
  final List<String>? equipmentIds;
  @JsonKey(includeIfNull: false)
  final String? notes;
  @JsonKey(includeIfNull: false,name: 'postal_code')
  final String? postalCode;
  @JsonKey(includeIfNull: false,name: 'resolution_hours')
  final int? resolutionHours;
  @JsonKey(includeIfNull: false,name: 'response_hours')
  final int? responseHours;

  /// The site covered. Left empty, the customer's address is used.
  @JsonKey(includeIfNull: false,name: 'site_name')
  final String? siteName;
  @JsonKey(name: 'start_date')
  final DateTime startDate;
  @JsonKey(includeIfNull: false)
  final String? street;
  final String title;

  /// The complete set of visit templates; templates left out are removed.
  @JsonKey(includeIfNull: false,name: 'visit_templates')
  final List<TemplateInput>? visitTemplates;

  Map<String, Object?> toJson() => _$ContractInputToJson(this);
}
