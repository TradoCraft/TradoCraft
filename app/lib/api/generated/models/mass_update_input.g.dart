// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mass_update_input.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MassUpdateInput _$MassUpdateInputFromJson(Map<String, dynamic> json) =>
    MassUpdateInput(
      action: MassAction.fromJson(json['action'] as String),
      body: json['body'] as String?,
      childIds: (json['child_ids'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      dryRun: json['dry_run'] as bool?,
      status: json['status'] as String?,
      subject: json['subject'] as String?,
    );

Map<String, dynamic> _$MassUpdateInputToJson(MassUpdateInput instance) =>
    <String, dynamic>{
      'action': instance.action,
      'body': ?instance.body,
      'child_ids': ?instance.childIds,
      'dry_run': ?instance.dryRun,
      'status': ?instance.status,
      'subject': ?instance.subject,
    };
