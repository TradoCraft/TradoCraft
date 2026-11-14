// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'contact_email.g.dart';

@JsonSerializable()
class ContactEmail {
  const ContactEmail({
    required this.email,
    required this.isPrimary,
  });
  
  factory ContactEmail.fromJson(Map<String, Object?> json) => _$ContactEmailFromJson(json);
  
  final String email;
  @JsonKey(name: 'is_primary')
  final bool isPrimary;

  Map<String, Object?> toJson() => _$ContactEmailToJson(this);
}
