// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'remark_history_entry.g.dart';

/// One remark text that was used before.
@JsonSerializable()
class RemarkHistoryEntry {
  const RemarkHistoryEntry({
    required this.lastQuotationNumber,
    required this.lastUsed,
    required this.text,
    required this.useCount,
  });
  
  factory RemarkHistoryEntry.fromJson(Map<String, Object?> json) => _$RemarkHistoryEntryFromJson(json);
  
  /// Number of the latest quotation that used the text.
  @JsonKey(name: 'last_quotation_number')
  final String lastQuotationNumber;

  /// Quote date of the latest quotation that used the text.
  @JsonKey(name: 'last_used')
  final DateTime lastUsed;
  final String text;

  /// Number of quotation lines that carry the text.
  @JsonKey(name: 'use_count')
  final int useCount;

  Map<String, Object?> toJson() => _$RemarkHistoryEntryToJson(this);
}
