// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'quotation_line_input.dart';

part 'quotation_input.g.dart';

@JsonSerializable()
class QuotationInput {
  const QuotationInput({
    required this.customerId,
    required this.lines,
    this.clearPowerGrid,
    this.deliveryCountryCode,
    this.notes,
    this.opportunityId,
    this.powerGridId,
    this.priceDate,
    this.purpose,
    this.quoteDate,
    this.validDays,
  });
  
  factory QuotationInput.fromJson(Map<String, Object?> json) => _$QuotationInputFromJson(json);
  
  /// `true` clears the stored grid ("any grid of the delivery country"); it wins over the keep.
  /// rule above and is refused (422) together with a `power_grid_id`. Absent or `false`: no effect.
  @JsonKey(includeIfNull: false,name: 'clear_power_grid')
  final bool? clearPowerGrid;
  @JsonKey(name: 'customer_id')
  final String customerId;

  /// ISO 3166 alpha-2 country the goods go to. Defaults to the customer's country for an.
  /// installation (on update: unchanged when omitted, unless the customer changes).
  @JsonKey(includeIfNull: false,name: 'delivery_country_code')
  final String? deliveryCountryCode;
  final List<QuotationLineInput> lines;
  @JsonKey(includeIfNull: false)
  final String? notes;

  /// Links the quotation to an open opportunity of the same customer.
  @JsonKey(includeIfNull: false,name: 'opportunity_id')
  final String? opportunityId;

  /// The power grid at the delivery country the goods are connected to; it must belong to that.
  /// country. On update: kept when omitted, unless the delivery country changes (then cleared).
  @JsonKey(includeIfNull: false,name: 'power_grid_id')
  final String? powerGridId;

  /// Date of the price list used. Defaults to the quote date (on update: unchanged).
  /// A date before the quote date needs the prices.backdate permission.
  @JsonKey(includeIfNull: false,name: 'price_date')
  final DateTime? priceDate;

  /// `installation` (default) or `stock`. On update: unchanged when omitted.
  @JsonKey(includeIfNull: false)
  final String? purpose;

  /// Defaults to today.
  @JsonKey(includeIfNull: false,name: 'quote_date')
  final DateTime? quoteDate;

  /// Defaults to 30 days.
  @JsonKey(includeIfNull: false,name: 'valid_days')
  final int? validDays;

  Map<String, Object?> toJson() => _$QuotationInputToJson(this);
}
