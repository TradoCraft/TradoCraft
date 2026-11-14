// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:json_annotation/json_annotation.dart';

import 'board_job.dart';
import 'board_technician.dart';
import 'settings.dart';
import 'skill.dart';

part 'board.g.dart';

@JsonSerializable()
class Board {
  const Board({
    required this.backlog,
    required this.from,
    required this.jobs,
    required this.settings,
    required this.skills,
    required this.technicians,
    required this.to,
  });
  
  factory Board.fromJson(Map<String, Object?> json) => _$BoardFromJson(json);
  
  /// Open jobs without a schedule or without a technician, most urgent first.
  final List<BoardJob> backlog;
  final DateTime from;

  /// Assigned jobs scheduled in the period.
  final List<BoardJob> jobs;
  final Settings settings;

  /// The skills catalogue (for filters).
  final List<Skill> skills;
  final List<BoardTechnician> technicians;
  final DateTime to;

  Map<String, Object?> toJson() => _$BoardToJson(this);
}
