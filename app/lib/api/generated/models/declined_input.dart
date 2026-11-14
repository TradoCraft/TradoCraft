// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'declined_input.g.dart';

@JsonSerializable()
class DeclinedInput {
  const DeclinedInput({
    required this.reason,
    this.signerName,
  });
  
  factory DeclinedInput.fromJson(Map<String, Object?> json) => _$DeclinedInputFromJson(json);
  
  /// Why the customer did not sign.
  final String reason;

  /// Who was asked, if known.
  @JsonKey(includeIfNull: false,name: 'signer_name')
  final String? signerName;

  Map<String, Object?> toJson() => _$DeclinedInputToJson(this);
}
