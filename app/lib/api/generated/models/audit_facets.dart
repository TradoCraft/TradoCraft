// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'audit_facets.g.dart';

/// What the filters of the viewer can offer.
@JsonSerializable()
class AuditFacets {
  const AuditFacets({
    required this.entities,
  });
  
  factory AuditFacets.fromJson(Map<String, Object?> json) => _$AuditFacetsFromJson(json);
  
  /// The kinds of record that have events in this company, alphabetically.
  final List<String> entities;

  Map<String, Object?> toJson() => _$AuditFacetsToJson(this);
}
