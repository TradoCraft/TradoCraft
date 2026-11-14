// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'invoice_summary.dart';

part 'invoice_page.g.dart';

/// A page of invoices.
@JsonSerializable()
class InvoicePage {
  const InvoicePage({
    required this.items,
    required this.total,
  });
  
  factory InvoicePage.fromJson(Map<String, Object?> json) => _$InvoicePageFromJson(json);
  
  /// The invoices on this page, newest first.
  final List<InvoiceSummary> items;

  /// Number of invoices matching the filters.
  final int total;

  Map<String, Object?> toJson() => _$InvoicePageToJson(this);
}
