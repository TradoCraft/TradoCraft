// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'apply_template_input.g.dart';

@JsonSerializable()
class ApplyTemplateInput {
  const ApplyTemplateInput({
    required this.templateId,
  });
  
  factory ApplyTemplateInput.fromJson(Map<String, Object?> json) => _$ApplyTemplateInputFromJson(json);
  
  @JsonKey(name: 'template_id')
  final String templateId;

  Map<String, Object?> toJson() => _$ApplyTemplateInputToJson(this);
}
