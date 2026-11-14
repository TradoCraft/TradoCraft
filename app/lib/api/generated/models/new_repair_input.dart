// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'new_repair_input.g.dart';

@JsonSerializable()
class NewRepairInput {
  const NewRepairInput({
    this.announced,
    this.contactId,
    this.customerId,
    this.customerReference,
    this.faultDescription,
    this.priority,
    this.productDescription,
    this.productId,
    this.serialNumber,
    this.ticketId,
    this.warranty,
  });
  
  factory NewRepairInput.fromJson(Map<String, Object?> json) => _$NewRepairInputFromJson(json);
  
  /// True when the customer announced it but it has not arrived yet.
  @JsonKey(includeIfNull: false)
  final bool? announced;
  @JsonKey(includeIfNull: false,name: 'contact_id')
  final String? contactId;

  /// Optional when `ticket_id` is given and the ticket has a customer.
  @JsonKey(includeIfNull: false,name: 'customer_id')
  final String? customerId;
  @JsonKey(includeIfNull: false,name: 'customer_reference')
  final String? customerReference;

  /// What is wrong. Defaults to the subject of the ticket.
  @JsonKey(includeIfNull: false,name: 'fault_description')
  final String? faultDescription;
  @JsonKey(includeIfNull: false)
  final String? priority;
  @JsonKey(includeIfNull: false,name: 'product_description')
  final String? productDescription;
  @JsonKey(includeIfNull: false,name: 'product_id')
  final String? productId;
  @JsonKey(includeIfNull: false,name: 'serial_number')
  final String? serialNumber;

  /// The ticket where the customer announced the repair.
  @JsonKey(includeIfNull: false,name: 'ticket_id')
  final String? ticketId;
  @JsonKey(includeIfNull: false)
  final String? warranty;

  Map<String, Object?> toJson() => _$NewRepairInputToJson(this);
}
