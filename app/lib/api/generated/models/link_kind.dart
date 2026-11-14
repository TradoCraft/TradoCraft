// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

/// The kind of record an item is linked to. Closed list, mirrored by the `CHECK` on.
/// `todo.items.link_kind` and by the app's link registry.
@JsonEnum()
enum LinkKind {
  @JsonValue('customer')
  customer('customer'),
  @JsonValue('quotation')
  quotation('quotation'),
  @JsonValue('order')
  order('order'),
  @JsonValue('ticket')
  ticket('ticket'),
  @JsonValue('repair')
  repair('repair'),
  @JsonValue('job')
  job('job'),
  @JsonValue('production_order')
  productionOrder('production_order'),
  @JsonValue('delivery')
  delivery('delivery'),
  @JsonValue('product')
  product('product'),
  @JsonValue('opportunity')
  opportunity('opportunity'),
  @JsonValue('purchase_order')
  purchaseOrder('purchase_order'),
  @JsonValue('goods_receipt')
  goodsReceipt('goods_receipt'),
  @JsonValue('supplier')
  supplier('supplier'),
  @JsonValue('supplier_invoice')
  supplierInvoice('supplier_invoice'),
  @JsonValue('kb_entry')
  kbEntry('kb_entry'),
  @JsonValue('stock_count')
  stockCount('stock_count'),
  /// Default value for all unparsed values, allows backward compatibility when adding new values on the backend.
  $unknown(null);

  const LinkKind(this.json);

  factory LinkKind.fromJson(String json) => values.firstWhere(
        (e) => e.json == json,
        orElse: () => $unknown,
      );

  final String? json;
  String toJson() {
    final value = json;
    if (value == null) {
      throw StateError('Cannot convert enum value with null JSON representation to String. '
          'This usually happens for \$unknown or @JsonValue(null) entries.');
    }
    return value as String;
  }

  @override
  String toString() => json?.toString() ?? super.toString();
  /// Returns all defined enum values excluding the $unknown value.
  static List<LinkKind> get $valuesDefined => values.where((value) => value != $unknown).toList();
}
