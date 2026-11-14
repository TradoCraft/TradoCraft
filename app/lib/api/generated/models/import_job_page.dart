// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'import_job.dart';

part 'import_job_page.g.dart';

@JsonSerializable()
class ImportJobPage {
  const ImportJobPage({
    required this.items,
    required this.total,
  });
  
  factory ImportJobPage.fromJson(Map<String, Object?> json) => _$ImportJobPageFromJson(json);
  
  final List<ImportJob> items;
  final int total;

  Map<String, Object?> toJson() => _$ImportJobPageToJson(this);
}
