// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'delegate_input.g.dart';

@JsonSerializable()
class DelegateInput {
  const DelegateInput({
    required this.toUserId,
    this.comment,
  });
  
  factory DelegateInput.fromJson(Map<String, Object?> json) => _$DelegateInputFromJson(json);
  
  /// Internal comment for the new owner; never sent to the customer.
  @JsonKey(includeIfNull: false)
  final String? comment;

  /// The new owner.
  @JsonKey(name: 'to_user_id')
  final String toUserId;

  Map<String, Object?> toJson() => _$DelegateInputToJson(this);
}
