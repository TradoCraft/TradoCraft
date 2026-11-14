// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'signature.g.dart';

@JsonSerializable()
class Signature {
  const Signature({
    required this.description,
    required this.group,
    required this.name,
    required this.usage,
  });
  
  factory Signature.fromJson(Map<String, Object?> json) => _$SignatureFromJson(json);
  
  final String description;
  final String group;
  final String name;

  /// How it is written, e.g. `round(x, digits?)`.
  final String usage;

  Map<String, Object?> toJson() => _$SignatureToJson(this);
}
