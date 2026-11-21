// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'media_update.g.dart';

@JsonSerializable()
class MediaUpdate {
  const MediaUpdate({
    this.caption,
    this.isDefault,
  });
  
  factory MediaUpdate.fromJson(Map<String, Object?> json) => _$MediaUpdateFromJson(json);
  
  @JsonKey(includeIfNull: false)
  final String? caption;

  /// `true` makes this the default (the previous default loses it); `false` is refused, pick.
  /// another item as the default instead.
  @JsonKey(includeIfNull: false,name: 'is_default')
  final bool? isDefault;

  Map<String, Object?> toJson() => _$MediaUpdateToJson(this);
}
