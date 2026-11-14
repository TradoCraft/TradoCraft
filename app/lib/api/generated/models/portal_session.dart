// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'portal_profile.dart';

part 'portal_session.g.dart';

@JsonSerializable()
class PortalSession {
  const PortalSession({
    required this.expiresAt,
    required this.profile,
    required this.token,
  });
  
  factory PortalSession.fromJson(Map<String, Object?> json) => _$PortalSessionFromJson(json);
  
  @JsonKey(name: 'expires_at')
  final DateTime expiresAt;
  final PortalProfile profile;

  /// Send as `Authorization: Bearer <token>` on every portal request.
  final String token;

  Map<String, Object?> toJson() => _$PortalSessionToJson(this);
}
