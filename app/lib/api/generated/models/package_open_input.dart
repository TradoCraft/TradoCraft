// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'package_open_input.g.dart';

@JsonSerializable()
class PackageOpenInput {
  const PackageOpenInput({
    required this.kind,
    this.customerId,
    this.note,
  });
  
  factory PackageOpenInput.fromJson(Map<String, Object?> json) => _$PackageOpenInputFromJson(json);
  
  /// Set or correct the sender now that the parcel is open.
  @JsonKey(includeIfNull: false,name: 'customer_id')
  final String? customerId;

  /// What the parcel is: repair | other | return_to_sender.
  final String kind;

  /// Required for `other` and `return_to_sender`: what it is, or why it goes back.
  @JsonKey(includeIfNull: false)
  final String? note;

  Map<String, Object?> toJson() => _$PackageOpenInputToJson(this);
}
