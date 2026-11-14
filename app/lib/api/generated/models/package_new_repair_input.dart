// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'package_new_repair_input.g.dart';

@JsonSerializable()
class PackageNewRepairInput {
  const PackageNewRepairInput({
    this.contactId,
    this.customerId,
    this.customerReference,
    this.faultDescription,
    this.productDescription,
    this.productId,
    this.serialNumber,
    this.ticketId,
  });
  
  factory PackageNewRepairInput.fromJson(Map<String, Object?> json) => _$PackageNewRepairInputFromJson(json);
  
  @JsonKey(includeIfNull: false,name: 'contact_id')
  final String? contactId;

  /// Defaults to the customer of the parcel.
  @JsonKey(includeIfNull: false,name: 'customer_id')
  final String? customerId;

  /// Defaults to the customer reference of the parcel.
  @JsonKey(includeIfNull: false,name: 'customer_reference')
  final String? customerReference;

  /// What is wrong. Defaults to the subject of the ticket, else to "To be determined at intake".
  @JsonKey(includeIfNull: false,name: 'fault_description')
  final String? faultDescription;
  @JsonKey(includeIfNull: false,name: 'product_description')
  final String? productDescription;
  @JsonKey(includeIfNull: false,name: 'product_id')
  final String? productId;
  @JsonKey(includeIfNull: false,name: 'serial_number')
  final String? serialNumber;
  @JsonKey(includeIfNull: false,name: 'ticket_id')
  final String? ticketId;

  Map<String, Object?> toJson() => _$PackageNewRepairInputToJson(this);
}
