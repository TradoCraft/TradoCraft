// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'configured_line_input.dart';

part 'configured_quotation_input.g.dart';

@JsonSerializable()
class ConfiguredQuotationInput {
  const ConfiguredQuotationInput({
    required this.customerId,
    required this.externalRef,
    required this.lines,
    required this.source,
    this.configuration,
    this.deliveryCountryCode,
    this.notes,
    this.powerGridId,
    this.priceZoneCode,
    this.purpose,
    this.strict,
    this.validDays,
  });
  
  factory ConfiguredQuotationInput.fromJson(Map<String, Object?> json) => _$ConfiguredQuotationInputFromJson(json);
  
  /// The configurator's own payload, stored verbatim on the quotation for traceability.
  @JsonKey(includeIfNull: false)
  final dynamic configuration;
  @JsonKey(name: 'customer_id')
  final String customerId;

  /// Defaults to the customer's country for an installation.
  @JsonKey(includeIfNull: false,name: 'delivery_country_code')
  final String? deliveryCountryCode;

  /// The configuration's identifier in that system. Importing the same source and reference.
  /// again updates the quotation (see the endpoint).
  @JsonKey(name: 'external_ref')
  final String externalRef;
  final List<ConfiguredLineInput> lines;
  @JsonKey(includeIfNull: false)
  final String? notes;
  @JsonKey(includeIfNull: false,name: 'power_grid_id')
  final String? powerGridId;

  /// The price zone the configurator expects. Prices always come from the customer's own zone;.
  /// a different value only adds a `price_zone_mismatch` warning (422 when `strict`).
  @JsonKey(includeIfNull: false,name: 'price_zone_code')
  final String? priceZoneCode;

  /// `installation` (default) or `stock`. On a re-import: unchanged when omitted.
  @JsonKey(includeIfNull: false)
  final String? purpose;

  /// The system the configuration comes from, e.g. `configurator`.
  final String source;

  /// Refuse the import (422) when a product code is unknown or the price zone differs, instead.
  /// of skipping the line with a warning.
  @JsonKey(includeIfNull: false)
  final bool? strict;

  /// Defaults to 30 days.
  @JsonKey(includeIfNull: false,name: 'valid_days')
  final int? validDays;

  Map<String, Object?> toJson() => _$ConfiguredQuotationInputToJson(this);
}
