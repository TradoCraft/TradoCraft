// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'admin_summary.dart';
import 'company.dart';

part 'bootstrap_result.g.dart';

/// Result of a successful bootstrap. Contains no secrets.
@JsonSerializable()
class BootstrapResult {
  const BootstrapResult({
    required this.admin,
    required this.authMode,
    required this.company,
  });
  
  factory BootstrapResult.fromJson(Map<String, Object?> json) => _$BootstrapResultFromJson(json);
  
  /// Its first administrator.
  final AdminSummary admin;

  /// `dev` or `oidc`: how the administrator signs in.
  @JsonKey(name: 'auth_mode')
  final String authMode;

  /// The new company.
  final Company company;

  Map<String, Object?> toJson() => _$BootstrapResultToJson(this);
}
