// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'update_approval_limits_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

UpdateApprovalLimitsInput _$UpdateApprovalLimitsInputFromJson(
  Map<String, dynamic> json,
) => UpdateApprovalLimitsInput(
  limits: (json['limits'] as List<dynamic>)
      .map((e) => RoleLimitInput.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$UpdateApprovalLimitsInputToJson(
  UpdateApprovalLimitsInput instance,
) => <String, dynamic>{'limits': instance.limits};
