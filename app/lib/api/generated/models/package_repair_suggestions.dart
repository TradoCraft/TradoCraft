// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'repair_suggestion.dart';

part 'package_repair_suggestions.g.dart';

@JsonSerializable()
class PackageRepairSuggestions {
  const PackageRepairSuggestions({
    required this.suggestions,
    this.proposedCustomerId,
    this.proposedCustomerName,
  });
  
  factory PackageRepairSuggestions.fromJson(Map<String, Object?> json) => _$PackageRepairSuggestionsFromJson(json);
  
  /// When the parcel has no customer yet: the customer of the best suggestion.
  @JsonKey(includeIfNull: false,name: 'proposed_customer_id')
  final String? proposedCustomerId;
  @JsonKey(includeIfNull: false,name: 'proposed_customer_name')
  final String? proposedCustomerName;

  /// At most 10, best first. Never applied automatically: confirm with `POST /packages/{id}/repairs`.
  final List<RepairSuggestion> suggestions;

  Map<String, Object?> toJson() => _$PackageRepairSuggestionsToJson(this);
}
