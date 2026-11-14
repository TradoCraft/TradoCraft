// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'package.dart';

part 'package_page.g.dart';

@JsonSerializable()
class PackagePage {
  const PackagePage({
    required this.items,
    required this.total,
  });
  
  factory PackagePage.fromJson(Map<String, Object?> json) => _$PackagePageFromJson(json);
  
  final List<Package> items;
  final int total;

  Map<String, Object?> toJson() => _$PackagePageToJson(this);
}
