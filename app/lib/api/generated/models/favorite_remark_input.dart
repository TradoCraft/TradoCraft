// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'favorite_remark_input.g.dart';

/// The body of the call that adds a customer remark in one language.
@JsonSerializable()
class FavoriteRemarkInput {
  const FavoriteRemarkInput({
    required this.text,
    this.overwrite,
  });
  
  factory FavoriteRemarkInput.fromJson(Map<String, Object?> json) => _$FavoriteRemarkInputFromJson(json);
  
  /// Replace a text that already exists in that language. Default `false`: answer 409 instead.
  @JsonKey(includeIfNull: false)
  final bool? overwrite;

  /// The remark; not blank, at most 2000 characters.
  final String text;

  Map<String, Object?> toJson() => _$FavoriteRemarkInputToJson(this);
}
