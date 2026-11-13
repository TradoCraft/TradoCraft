// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'todo_counts.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TodoCounts _$TodoCountsFromJson(Map<String, dynamic> json) => TodoCounts(
  dueToday: (json['due_today'] as num).toInt(),
  open: (json['open'] as num).toInt(),
  overdue: (json['overdue'] as num).toInt(),
);

Map<String, dynamic> _$TodoCountsToJson(TodoCounts instance) =>
    <String, dynamic>{
      'due_today': instance.dueToday,
      'open': instance.open,
      'overdue': instance.overdue,
    };
