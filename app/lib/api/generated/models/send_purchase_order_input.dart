// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'send_purchase_order_input.g.dart';

/// Who the order goes to and in which language, when they differ from the supplier's own.
@JsonSerializable()
class SendPurchaseOrderInput {
  const SendPurchaseOrderInput({
    this.lang,
    this.to,
  });
  
  factory SendPurchaseOrderInput.fromJson(Map<String, Object?> json) => _$SendPurchaseOrderInputFromJson(json);
  
  /// nl | fr | en | de | es. Default: the supplier's language.
  @JsonKey(includeIfNull: false)
  final String? lang;

  /// Default: the supplier's e-mail address.
  @JsonKey(includeIfNull: false)
  final String? to;

  Map<String, Object?> toJson() => _$SendPurchaseOrderInputToJson(this);
}
