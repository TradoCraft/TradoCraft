// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'reader_link.g.dart';

@JsonSerializable()
class ReaderLink {
  const ReaderLink({
    required this.id,
    required this.number,
    required this.title,
  });
  
  factory ReaderLink.fromJson(Map<String, Object?> json) => _$ReaderLinkFromJson(json);
  
  final String id;
  final String number;
  final String title;

  Map<String, Object?> toJson() => _$ReaderLinkToJson(this);
}
