// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'company.dart';
import 'me_module.dart';
import 'membership.dart';

part 'me.g.dart';

/// The authenticated user, the active company and all companies they can switch to.
@JsonSerializable()
class Me {
  const Me({
    required this.company,
    required this.displayName,
    required this.email,
    required this.memberships,
    required this.modules,
    required this.permissions,
    required this.roles,
    required this.userId,
  });
  
  factory Me.fromJson(Map<String, Object?> json) => _$MeFromJson(json);
  
  final Company company;
  @JsonKey(name: 'display_name')
  final String displayName;
  final String email;
  final List<Membership> memberships;

  /// Every module with whether it is on for this user in the active company.
  final List<MeModule> modules;

  /// Permissions after roles and disabled modules are applied.
  final List<String> permissions;
  final List<String> roles;
  @JsonKey(name: 'user_id')
  final String userId;

  Map<String, Object?> toJson() => _$MeToJson(this);
}
