// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'membership.g.dart';

@JsonSerializable()
class Membership {
  const Membership({
    required this.companyId,
    required this.companyName,
    required this.isDefault,
    required this.roles,
  });
  
  factory Membership.fromJson(Map<String, Object?> json) => _$MembershipFromJson(json);
  
  @JsonKey(name: 'company_id')
  final String companyId;
  @JsonKey(name: 'company_name')
  final String companyName;
  @JsonKey(name: 'is_default')
  final bool isDefault;
  final List<String> roles;

  Map<String, Object?> toJson() => _$MembershipToJson(this);
}
