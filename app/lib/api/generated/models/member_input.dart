// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'member_input.g.dart';

@JsonSerializable()
class MemberInput {
  const MemberInput({
    required this.userId,
    this.isLead,
  });
  
  factory MemberInput.fromJson(Map<String, Object?> json) => _$MemberInputFromJson(json);
  
  @JsonKey(includeIfNull: false,name: 'is_lead')
  final bool? isLead;
  @JsonKey(name: 'user_id')
  final String userId;

  Map<String, Object?> toJson() => _$MemberInputToJson(this);
}
