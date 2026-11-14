// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'report_op.dart';

part 'report_filter.g.dart';

/// A filter condition on one field.
@JsonSerializable()
class ReportFilter {
  const ReportFilter({
    required this.field,
    required this.op,
    this.value,
  });
  
  factory ReportFilter.fromJson(Map<String, Object?> json) => _$ReportFilterFromJson(json);
  
  final String field;
  final ReportOp op;

  /// A string, number or boolean; an array for `in`; ignored for `is_null` and `not_null`.
  /// Dates are `YYYY-MM-DD`, also for date-time fields (compared as UTC days).
  ///
  /// On a date or date-time field the value may instead be a relative date, an object that is.
  /// resolved against today each time the report runs (so a saved report stays live):.
  /// `{"relative": "<token>"}` with the token `today`, `yesterday`, `this_week`, `last_week`.
  /// (weeks start on Monday), `this_month`, `last_month`, `this_quarter`, `last_quarter`,.
  /// `this_year` or `last_year`; or `{"relative": "last_n_days", "n": 30}` (the 30 days up to and.
  /// including today) and `{"relative": "next_n_days", "n": 7}` (today and the 6 days after),.
  /// with `n` from 1 to 3660. Each token is a range of days. `eq` matches the whole range, `ne`.
  /// everything outside it; `gte` and `lt` compare with the first day, `gt` and `lte` with the.
  /// last day (`gte last_month` is "from the start of last month", `gt last_month` is "after.
  /// last month", `lte` and `lt` the other way round). For a single day (`today`,.
  /// `yesterday`) all operators therefore read naturally. Not allowed with `in`, `is_null` and.
  /// `not_null`, or on other field types.
  @JsonKey(includeIfNull: false)
  final dynamic value;

  Map<String, Object?> toJson() => _$ReportFilterToJson(this);
}
