// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'package_new_repair_input.dart';

part 'package_repair_link_input.g.dart';

@JsonSerializable()
class PackageRepairLinkInput {
  const PackageRepairLinkInput({
    this.clientId,
    this.confirmCustomerMismatch,
    this.expectedStatus,
    this.newRepair,
    this.repairId,
  });
  
  factory PackageRepairLinkInput.fromJson(Map<String, Object?> json) => _$PackageRepairLinkInputFromJson(json);
  
  /// A key chosen by the app for `new_repair`: a retry returns the repair created the first time.
  @JsonKey(includeIfNull: false,name: 'client_id')
  final String? clientId;

  /// Link although the customer of the parcel is another than the customer of the repair.
  @JsonKey(includeIfNull: false,name: 'confirm_customer_mismatch')
  final bool? confirmCustomerMismatch;

  /// The status the app saw on `repair_id` (usually `announced`); 409 if someone else moved it meanwhile.
  @JsonKey(includeIfNull: false,name: 'expected_status')
  final String? expectedStatus;

  /// Nothing matched: create a new repair, already received, from this parcel.
  @JsonKey(includeIfNull: false,name: 'new_repair')
  final PackageNewRepairInput? newRepair;

  /// Confirm a suggestion: link this announced (or already received) repair. Give this or `new_repair`.
  @JsonKey(includeIfNull: false,name: 'repair_id')
  final String? repairId;

  Map<String, Object?> toJson() => _$PackageRepairLinkInputToJson(this);
}
