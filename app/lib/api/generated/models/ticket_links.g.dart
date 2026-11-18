// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ticket_links.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TicketLinks _$TicketLinksFromJson(Map<String, dynamic> json) => TicketLinks(
  children: (json['children'] as List<dynamic>)
      .map((e) => LinkedTicket.fromJson(e as Map<String, dynamic>))
      .toList(),
  duplicates: (json['duplicates'] as List<dynamic>)
      .map((e) => LinkedTicket.fromJson(e as Map<String, dynamic>))
      .toList(),
  related: (json['related'] as List<dynamic>)
      .map((e) => LinkedTicket.fromJson(e as Map<String, dynamic>))
      .toList(),
  duplicateOf: json['duplicate_of'] == null
      ? null
      : LinkedTicket.fromJson(json['duplicate_of'] as Map<String, dynamic>),
  parent: json['parent'] == null
      ? null
      : LinkedTicket.fromJson(json['parent'] as Map<String, dynamic>),
);

Map<String, dynamic> _$TicketLinksToJson(TicketLinks instance) =>
    <String, dynamic>{
      'children': instance.children,
      'duplicate_of': ?instance.duplicateOf,
      'duplicates': instance.duplicates,
      'parent': ?instance.parent,
      'related': instance.related,
    };
