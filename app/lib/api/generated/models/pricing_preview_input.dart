// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'quotation_line_input.dart';

part 'pricing_preview_input.g.dart';

@JsonSerializable()
class PricingPreviewInput {
  const PricingPreviewInput({
    required this.customerId,
    required this.lines,
    this.buildingConstructionYear,
    this.clearBuildingConstructionYear,
    this.deliveryCountryCode,
    this.opportunityId,
    this.powerGridId,
    this.priceDate,
    this.purpose,
    this.quotationId,
    this.quoteDate,
    this.vatRegimeOverride,
  });
  
  factory PricingPreviewInput.fromJson(Map<String, Object?> json) => _$PricingPreviewInputFromJson(json);
  
  /// Building construction year for renovation VAT preview (800..=2200).
  @JsonKey(includeIfNull: false,name: 'building_construction_year')
  final int? buildingConstructionYear;

  /// Explicitly clear the year instead of inheriting from the opportunity.
  @JsonKey(includeIfNull: false,name: 'clear_building_construction_year')
  final bool? clearBuildingConstructionYear;
  @JsonKey(name: 'customer_id')
  final String customerId;

  /// Defaults to the customer's country.
  @JsonKey(includeIfNull: false,name: 'delivery_country_code')
  final String? deliveryCountryCode;
  final List<QuotationLineInput> lines;

  /// Optional opportunity to inherit `building_construction_year` from when omitted.
  @JsonKey(includeIfNull: false,name: 'opportunity_id')
  final String? opportunityId;
  @JsonKey(includeIfNull: false,name: 'power_grid_id')
  final String? powerGridId;

  /// Price list date; defaults to the quote date.
  @JsonKey(includeIfNull: false,name: 'price_date')
  final DateTime? priceDate;

  /// `installation` (default) or `stock`; a stock purpose skips the power grid warnings.
  @JsonKey(includeIfNull: false)
  final String? purpose;

  /// The saved draft quotation being edited. When it belongs to the caller's company (else 404).
  /// and is a draft with a quoted shipping cost, and a product line still needs a shipping quote,.
  /// the preview also contains the `SHIPPING` line (as `shipping::shipping_line` builds it) in.
  /// `lines`, `vat_groups` and the totals. Ignored for quotations that are not drafts.
  @JsonKey(includeIfNull: false,name: 'quotation_id')
  final String? quotationId;
  @JsonKey(includeIfNull: false,name: 'quote_date')
  final DateTime? quoteDate;

  /// Explicit VAT regime override to preview (`domestic`, `domestic_reverse_charge`, `intra_eu`, `outside_eu`).
  @JsonKey(includeIfNull: false,name: 'vat_regime_override')
  final String? vatRegimeOverride;

  Map<String, Object?> toJson() => _$PricingPreviewInputToJson(this);
}
