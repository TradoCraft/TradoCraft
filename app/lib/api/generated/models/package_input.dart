// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'package_input.g.dart';

@JsonSerializable()
class PackageInput {
  const PackageInput({
    this.carrier,
    this.clientId,
    this.condition,
    this.conditionNote,
    this.customerId,
    this.customerReference,
    this.notes,
    this.parcelCount,
    this.senderName,
    this.trackingNumber,
  });
  
  factory PackageInput.fromJson(Map<String, Object?> json) => _$PackageInputFromJson(json);
  
  @JsonKey(includeIfNull: false)
  final String? carrier;

  /// A key chosen by the app: registering the same key again returns the first parcel.
  @JsonKey(includeIfNull: false,name: 'client_id')
  final String? clientId;

  /// intact | damaged | opened | wet. Defaults to intact.
  @JsonKey(includeIfNull: false)
  final String? condition;
  @JsonKey(includeIfNull: false,name: 'condition_note')
  final String? conditionNote;
  @JsonKey(includeIfNull: false,name: 'customer_id')
  final String? customerId;
  @JsonKey(includeIfNull: false,name: 'customer_reference')
  final String? customerReference;
  @JsonKey(includeIfNull: false)
  final String? notes;
  @JsonKey(includeIfNull: false,name: 'parcel_count')
  final int? parcelCount;

  /// The sender as written on the label.
  @JsonKey(includeIfNull: false,name: 'sender_name')
  final String? senderName;
  @JsonKey(includeIfNull: false,name: 'tracking_number')
  final String? trackingNumber;

  Map<String, Object?> toJson() => _$PackageInputToJson(this);
}
