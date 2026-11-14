// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'setup_status.g.dart';

/// Whether this server can be set up, and what the wizard has to ask for.
@JsonSerializable()
class SetupStatus {
  const SetupStatus({
    required this.authMode,
    required this.needsSetup,
    required this.tokenRequired,
  });
  
  factory SetupStatus.fromJson(Map<String, Object?> json) => _$SetupStatusFromJson(json);
  
  /// `dev` (the admin e-mail becomes the dev user) or `oidc` (sign in through the identity provider).
  @JsonKey(name: 'auth_mode')
  final String authMode;

  /// True while no company exists and bootstrapping is enabled on this server.
  @JsonKey(name: 'needs_setup')
  final bool needsSetup;

  /// True when `POST /setup/bootstrap` must carry the `BOOTSTRAP_TOKEN`.
  @JsonKey(name: 'token_required')
  final bool tokenRequired;

  Map<String, Object?> toJson() => _$SetupStatusToJson(this);
}
