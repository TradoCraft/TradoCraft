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
    this.buildingConstructionYear,
    this.clearBuildingConstructionYear,
    this.clearPowerGrid,
    this.clearVatRegimeOverride,
    this.deliveryCountryCode,
    this.notes,
    this.opportunityId,
    this.powerGridId,
    this.priceDate,
    this.purpose,
    this.quoteDate,
    this.validDays,
    this.vatRegimeOverride,
  });
  
  factory QuotationInput.fromJson(Map<String, Object?> json) => _$QuotationInputFromJson(json);
  
  /// Year the site's building was constructed (800..=2200). Inherited from `opportunity_id` when omitted on create.
  @JsonKey(includeIfNull: false,name: 'building_construction_year')
  final int? buildingConstructionYear;

  /// `true` clears `building_construction_year` on update; refused (422) together with a year.
  @JsonKey(includeIfNull: false,name: 'clear_building_construction_year')
  final bool? clearBuildingConstructionYear;

  /// `true` clears the stored grid ("any grid of the delivery country"); it wins over the keep.
  /// rule above and is refused (422) together with a `power_grid_id`. Absent or `false`: no effect.
  @JsonKey(includeIfNull: false,name: 'clear_power_grid')
  final bool? clearPowerGrid;

  /// `true` clears any previous `vat_regime_override` on update so auto-resolution applies again.
  @JsonKey(includeIfNull: false,name: 'clear_vat_regime_override')
  final bool? clearVatRegimeOverride;
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

  /// Explicit VAT regime override (`domestic`, `domestic_reverse_charge`, `intra_eu`, `outside_eu`).
  /// When omitted on create, derived from customer regime and purpose; on update kept unless cleared.
  @JsonKey(includeIfNull: false,name: 'vat_regime_override')
  final String? vatRegimeOverride;

  Map<String, Object?> toJson() => _$QuotationInputToJson(this);
}
