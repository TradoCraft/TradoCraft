// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'detach_input.g.dart';

@JsonSerializable()
class DetachInput {
  const DetachInput({
    this.childStatus,
  });
  
  factory DetachInput.fromJson(Map<String, Object?> json) => _$DetachInputFromJson(json);
  
  /// What happens to the removed component: in_stock (default) or scrapped.
  @JsonKey(includeIfNull: false,name: 'child_status')
  final String? childStatus;

  Map<String, Object?> toJson() => _$DetachInputToJson(this);
}
