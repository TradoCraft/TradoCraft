// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'mrp_proposal.dart';

part 'mrp_conversion.g.dart';

@JsonSerializable()
class MrpConversion {
  const MrpConversion({
    required this.convertedTo,
    required this.number,
    required this.proposal,
  });
  
  factory MrpConversion.fromJson(Map<String, Object?> json) => _$MrpConversionFromJson(json);
  
  /// The purchase order (draft) or the production order made.
  @JsonKey(name: 'converted_to')
  final String convertedTo;

  /// Its number.
  final String number;
  final MrpProposal proposal;

  Map<String, Object?> toJson() => _$MrpConversionToJson(this);
}
