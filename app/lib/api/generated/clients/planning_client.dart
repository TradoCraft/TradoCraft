// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../models/absence.dart';
import '../models/absence_input.dart';
import '../models/board.dart';
import '../models/job_skills_input.dart';
import '../models/schedule_input.dart';
import '../models/schedule_result.dart';
import '../models/settings.dart';
import '../models/skill.dart';
import '../models/skill_input.dart';
import '../models/suggestion_out.dart';
import '../models/technician_hours.dart';
import '../models/user_skill.dart';
import '../models/user_skills_input.dart';
import '../models/working_hours_input.dart';

part 'planning_client.g.dart';

@RestApi()
abstract class PlanningClient {
  factory PlanningClient(Dio dio, {String? baseUrl}) = _PlanningClient;

  /// Absences of the company in a period (planners), or of oneself.
  ///
  /// [from] - Absences ending on or after this day.
  ///
  /// [to] - Absences starting on or before this day.
  @GET('/api/v1/planning/absences')
  Future<List<Absence>> listAbsences({
    @Query('user_id') String? userId,
    @Query('from') DateTime? from,
    @Query('to') DateTime? to,
  });

  @POST('/api/v1/planning/absences')
  Future<Absence> createAbsence({
    @Body() required AbsenceInput body,
  });

  @PUT('/api/v1/planning/absences/{id}')
  Future<Absence> updateAbsence({
    @Path('id') required String id,
    @Body() required AbsenceInput body,
  });

  @DELETE('/api/v1/planning/absences/{id}')
  Future<void> deleteAbsence({
    @Path('id') required String id,
  });

  /// Technicians with skills, working hours and absences, the jobs scheduled in the period, and the.
  /// backlog of jobs still to plan.
  ///
  /// [from] - First day (in the company's time zone).
  ///
  /// [to] - Last day, inclusive.
  @GET('/api/v1/planning/board')
  Future<Board> getPlanningBoard({
    @Query('from') required DateTime from,
    @Query('to') required DateTime to,
  });

  /// Schedules a job and assigns its technicians in one step. Completed and cancelled jobs are.
  /// refused (409). Errors among the conflicts (a double booking, an absence) refuse the change.
  /// (409) unless `force=true`; warnings never do. The conflicts are returned either way.
  /// The assigned technicians are told by mail (not the planner).
  ///
  /// [dryRun] - Only report the conflicts; change nothing (used while dragging).
  ///
  /// [force] - Schedule although there are errors (e.g. a technician on holiday).
  @PUT('/api/v1/planning/jobs/{id}/schedule')
  Future<ScheduleResult> scheduleJob({
    @Path('id') required String id,
    @Body() required ScheduleInput body,
    @Query('dry_run') bool? dryRun,
    @Query('force') bool? force,
  });

  /// The skills a field job requires.
  @GET('/api/v1/planning/jobs/{id}/skills')
  Future<List<Skill>> getJobSkills({
    @Path('id') required String id,
  });

  @PUT('/api/v1/planning/jobs/{id}/skills')
  Future<List<Skill>> setJobSkills({
    @Path('id') required String id,
    @Body() required JobSkillsInput body,
  });

  /// The planning settings of the company (defaults until an administrator saves them).
  @GET('/api/v1/planning/settings')
  Future<Settings> getPlanningSettings();

  @PUT('/api/v1/planning/settings')
  Future<Settings> updatePlanningSettings({
    @Body() required Settings body,
  });

  /// The skills catalogue of the company.
  @GET('/api/v1/planning/skills')
  Future<List<Skill>> listSkills();

  @POST('/api/v1/planning/skills')
  Future<Skill> createSkill({
    @Body() required SkillInput body,
  });

  @PUT('/api/v1/planning/skills/{id}')
  Future<Skill> updateSkill({
    @Path('id') required String id,
    @Body() required SkillInput body,
  });

  /// Deleting a skill removes it from technicians and jobs.
  @DELETE('/api/v1/planning/skills/{id}')
  Future<void> deleteSkill({
    @Path('id') required String id,
  });

  /// Ranked technician and slot suggestions for a job: technicians with the required skills first,.
  /// then the earliest day, then the slot that leaves the least unused time in its gap. Slots lie.
  /// inside working hours, outside absences and keep the travel buffer to other jobs.
  ///
  /// [from] - First day to look at (default today).
  ///
  /// [to] - Last day, inclusive (default six days after `from`).
  @GET('/api/v1/planning/suggestions/{job_id}')
  Future<List<SuggestionOut>> suggestSlots({
    @Path('job_id') required String jobId,
    @Query('from') DateTime? from,
    @Query('to') DateTime? to,
  });

  /// The skills of a technician (planners, or the technician themselves).
  @GET('/api/v1/planning/users/{id}/skills')
  Future<List<UserSkill>> getUserSkills({
    @Path('id') required String id,
  });

  @PUT('/api/v1/planning/users/{id}/skills')
  Future<List<UserSkill>> setUserSkills({
    @Path('id') required String id,
    @Body() required UserSkillsInput body,
  });

  /// Working hours: the rows of one user (themselves, or a planner), the company default rows.
  /// (`defaults=true`, anyone), or every row (planners).
  ///
  /// [userId] - Rows of this user only.
  ///
  /// [defaults] - The company default rows.
  @GET('/api/v1/planning/working-hours')
  Future<List<TechnicianHours>> listWorkingHours({
    @Query('user_id') String? userId,
    @Query('defaults') bool? defaults,
  });

  @PUT('/api/v1/planning/working-hours')
  Future<List<TechnicianHours>> setWorkingHours({
    @Body() required WorkingHoursInput body,
  });
}
