// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'job_signature.g.dart';

@JsonSerializable()
class JobSignature {
  const JobSignature({
    required this.declineReason,
    required this.declined,
    required this.hasImage,
    required this.signedAt,
    required this.signerName,
    this.capturedByName,
  });
  
  factory JobSignature.fromJson(Map<String, Object?> json) => _$JobSignatureFromJson(json);
  
  @JsonKey(includeIfNull: false,name: 'captured_by_name')
  final String? capturedByName;
  @JsonKey(name: 'decline_reason')
  final String declineReason;

  /// The customer declined to sign.
  final bool declined;

  /// A signature image is stored: fetch it from `/field/jobs/{id}/signature`.
  @JsonKey(name: 'has_image')
  final bool hasImage;
  @JsonKey(name: 'signed_at')
  final DateTime signedAt;
  @JsonKey(name: 'signer_name')
  final String signerName;

  Map<String, Object?> toJson() => _$JobSignatureToJson(this);
}
