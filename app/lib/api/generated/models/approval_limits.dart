// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'role_limit.dart';

part 'approval_limits.g.dart';

/// The approval limits of the company and the caller's own.
@JsonSerializable()
class ApprovalLimits {
  const ApprovalLimits({
    required this.currency,
    required this.roles,
    this.yourLimit,
  });
  
  factory ApprovalLimits.fromJson(Map<String, Object?> json) => _$ApprovalLimitsFromJson(json);
  
  /// The limits are amounts of the order's net total in this currency.
  final String currency;

  /// Every role whose approvals can be limited, with its limit.
  final List<RoleLimit> roles;

  /// What the caller may approve at most; `None` when the caller has no limit.
  @JsonKey(includeIfNull: false,name: 'your_limit')
  final String? yourLimit;

  Map<String, Object?> toJson() => _$ApprovalLimitsToJson(this);
}
