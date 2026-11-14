// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'order_line.dart';
import 'order_revision_info.dart';
import 'order_summary.dart';
import 'sales_suggestion.dart';
import 'sales_warning.dart';

part 'order.g.dart';

/// One revision of an order (the latest unless asked otherwise) with its lines.
@JsonSerializable()
class Order {
  const Order({
    required this.cancelReason,
    required this.confirmationNote,
    required this.createdAt,
    required this.lines,
    required this.notes,
    required this.order,
    required this.revision,
    required this.revisionStatus,
    required this.revisions,
    required this.suggestions,
    required this.vatTotal,
    required this.warnings,
    this.confirmedAt,
    this.confirmedBy,
    this.confirmedRevision,
    this.confirmedVia,
  });
  
  factory Order.fromJson(Map<String, Object?> json) => _$OrderFromJson(json);
  
  @JsonKey(name: 'cancel_reason')
  final String cancelReason;
  @JsonKey(name: 'confirmation_note')
  final String confirmationNote;
  @JsonKey(includeIfNull: false,name: 'confirmed_at')
  final DateTime? confirmedAt;

  /// A staff user id (`confirmed_via` = staff) or a contact id (portal).
  @JsonKey(includeIfNull: false,name: 'confirmed_by')
  final String? confirmedBy;
  @JsonKey(includeIfNull: false,name: 'confirmed_revision')
  final int? confirmedRevision;

  /// staff | portal
  @JsonKey(includeIfNull: false,name: 'confirmed_via')
  final String? confirmedVia;
  @JsonKey(name: 'created_at')
  final DateTime createdAt;
  final List<OrderLine> lines;
  final String notes;
  final OrderSummary order;

  /// The revision these lines and totals belong to.
  final int revision;
  @JsonKey(name: 'revision_status')
  final String revisionStatus;
  final List<OrderRevisionInfo> revisions;

  /// Products worth adding; only filled by the confirm call.
  final List<SalesSuggestion> suggestions;
  @JsonKey(name: 'vat_total')
  final String vatTotal;

  /// Power grid and incompatible-product hints; only filled by the confirm call. Never blocking.
  final List<SalesWarning> warnings;

  Map<String, Object?> toJson() => _$OrderToJson(this);
}
