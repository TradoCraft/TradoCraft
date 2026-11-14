// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'order_line_edit.dart';

part 'order_edit_input.g.dart';

/// Changes to a draft revision. Lines that are left out are removed; prices and rebates stay as.
/// agreed on the quotation, the totals are recomputed by the server.
@JsonSerializable()
class OrderEditInput {
  const OrderEditInput({
    required this.lines,
    this.clearPowerGrid,
    this.customerReference,
    this.deliveryCountryCode,
    this.notes,
    this.powerGridId,
    this.purpose,
  });
  
  factory OrderEditInput.fromJson(Map<String, Object?> json) => _$OrderEditInputFromJson(json);
  
  /// `true` clears the grid ("any grid of the delivery country"); it wins over keeping the stored.
  /// one and is refused (422) together with a `power_grid_id`. Absent or `false`: no effect.
  @JsonKey(includeIfNull: false,name: 'clear_power_grid')
  final bool? clearPowerGrid;
  @JsonKey(includeIfNull: false,name: 'customer_reference')
  final String? customerReference;

  /// Delivery country (ISO alpha-2); unchanged when omitted.
  @JsonKey(includeIfNull: false,name: 'delivery_country_code')
  final String? deliveryCountryCode;
  final List<OrderLineEdit> lines;
  @JsonKey(includeIfNull: false)
  final String? notes;

  /// The power grid at the delivery country (the new one when it changes, else the stored one);.
  /// it must belong to it (422). Unchanged when omitted, except that a grid the new delivery.
  /// country does not have is cleared.
  @JsonKey(includeIfNull: false,name: 'power_grid_id')
  final String? powerGridId;

  /// `installation` or `stock`; unchanged when omitted. Cannot be changed after confirmation.
  @JsonKey(includeIfNull: false)
  final String? purpose;

  Map<String, Object?> toJson() => _$OrderEditInputToJson(this);
}
