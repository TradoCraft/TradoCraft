// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'send_now_result.g.dart';

@JsonSerializable()
class SendNowResult {
  const SendNowResult({required this.mails});

  factory SendNowResult.fromJson(Map<String, Object?> json) =>
      _$SendNowResultFromJson(json);

  /// Mails queued.
  final int mails;

  Map<String, Object?> toJson() => _$SendNowResultToJson(this);
}
