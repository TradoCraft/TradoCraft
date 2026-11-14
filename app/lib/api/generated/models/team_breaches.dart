// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

part 'team_breaches.g.dart';

@JsonSerializable()
class TeamBreaches {
  const TeamBreaches({
    required this.breached,
    required this.team,
    required this.tickets,
    this.teamId,
  });
  
  factory TeamBreaches.fromJson(Map<String, Object?> json) => _$TeamBreachesFromJson(json);
  
  final int breached;
  final String team;
  @JsonKey(includeIfNull: false,name: 'team_id')
  final String? teamId;
  final int tickets;

  Map<String, Object?> toJson() => _$TeamBreachesToJson(this);
}
