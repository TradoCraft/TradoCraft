// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../models/assignment_input.dart';
import '../models/business_calendar.dart';
import '../models/calendar_input.dart';
import '../models/call_input.dart';
import '../models/convert_ticket_input.dart';
import '../models/csat_info.dart';
import '../models/csat_input.dart';
import '../models/delegate_input.dart';
import '../models/dry_run.dart';
import '../models/dry_run_input.dart';
import '../models/escalate_input.dart';
import '../models/file_info.dart';
import '../models/helpdesk_settings.dart';
import '../models/holiday.dart';
import '../models/holiday_input.dart';
import '../models/inbound_result.dart';
import '../models/lead_input.dart';
import '../models/mailbox.dart';
import '../models/mailbox_input.dart';
import '../models/merge_input.dart';
import '../models/new_ticket_input.dart';
import '../models/note_input.dart';
import '../models/prepared_answer.dart';
import '../models/prepared_answer_input.dart';
import '../models/presence_entry.dart';
import '../models/presence_input.dart';
import '../models/production_question_input.dart';
import '../models/rendered_answer.dart';
import '../models/reply_input.dart';
import '../models/report.dart';
import '../models/rule.dart';
import '../models/rule_input.dart';
import '../models/rule_order.dart';
import '../models/settings_input.dart';
import '../models/sla_notice_settings.dart';
import '../models/sla_policies_input.dart';
import '../models/sla_policy.dart';
import '../models/split_input.dart';
import '../models/tag_count.dart';
import '../models/tag_input.dart';
import '../models/team.dart';
import '../models/team_input.dart';
import '../models/ticket_detail.dart';
import '../models/ticket_input.dart';
import '../models/ticket_page.dart';
import '../models/time_entries.dart';
import '../models/time_entry_input.dart';
import '../models/timeline_item.dart';
import '../models/watcher.dart';
import '../models/watcher_input.dart';

part 'helpdesk_client.g.dart';

@RestApi()
abstract class HelpdeskClient {
  factory HelpdeskClient(Dio dio, {String? baseUrl}) = _HelpdeskClient;

  /// What the customer sees before rating. Reading changes nothing, so mail scanners that open.
  /// links do not use up the token.
  @GET('/api/v1/csat/{token}')
  Future<CsatInfo> getCsat({
    @Path('token') required String token,
  });

  /// Records the rating. The token works once and only until it expires.
  @POST('/api/v1/csat/{token}')
  Future<CsatInfo> rateCsat({
    @Path('token') required String token,
    @Body() required CsatInput body,
  });

  /// Shows which rules would match the ticket for an event and what they would change, without.
  /// changing anything.
  @POST('/api/v1/helpdesk/automation/dry-run')
  Future<DryRun> dryRun({
    @Body() required DryRunInput body,
  });

  /// Sets the order in which rules run. The list must contain every rule of the company once.
  @PUT('/api/v1/helpdesk/automation/order')
  Future<List<Rule>> reorderRules({
    @Body() required RuleOrder body,
  });

  @GET('/api/v1/helpdesk/automation/rules')
  Future<List<Rule>> listRules();

  @POST('/api/v1/helpdesk/automation/rules')
  Future<Rule> createRule({
    @Body() required RuleInput body,
  });

  @PUT('/api/v1/helpdesk/automation/rules/{id}')
  Future<Rule> updateRule({
    @Path('id') required String id,
    @Body() required RuleInput body,
  });

  @DELETE('/api/v1/helpdesk/automation/rules/{id}')
  Future<void> deleteRule({
    @Path('id') required String id,
  });

  /// [teamId] - The team the calendar is for; without it the company calendar.
  @GET('/api/v1/helpdesk/calendar')
  Future<BusinessCalendar> getCalendar({
    @Query('team_id') String? teamId,
  });

  /// Sets the working week and time zone and switches the calendar on or off, for the company or,.
  /// with `team_id`, for one team (which then stops using the company's). Open tickets it applies.
  /// to get new due times.
  ///
  /// [teamId] - The team the calendar is for; without it the company calendar.
  @PUT('/api/v1/helpdesk/calendar')
  Future<BusinessCalendar> putCalendar({
    @Body() required CalendarInput body,
    @Query('team_id') String? teamId,
  });

  /// Removes a team's own calendar and its holidays: the team uses the company's again. Open.
  /// tickets of the team get new due times.
  @DELETE('/api/v1/helpdesk/calendar')
  Future<BusinessCalendar> deleteTeamCalendar({
    @Query('team_id') required String teamId,
  });

  /// [teamId] - The team the calendar is for; without it the company calendar.
  @POST('/api/v1/helpdesk/calendar/holidays')
  Future<Holiday> addHoliday({
    @Body() required HolidayInput body,
    @Query('team_id') String? teamId,
  });

  @DELETE('/api/v1/helpdesk/calendar/holidays/{id}')
  Future<void> deleteHoliday({
    @Path('id') required String id,
  });

  /// Logs a phone call. The caller is looked up by phone number; the call is added to the given.
  /// ticket, or a new ticket is opened for it.
  @POST('/api/v1/helpdesk/calls')
  Future<TicketDetail> logCall({
    @Body() required CallInput body,
  });

  /// Imports a raw e-mail (RFC 5322, e.g. a saved .eml file) as if it had arrived in the mailbox.
  @POST('/api/v1/helpdesk/inbound')
  Future<InboundResult> inbound({
    @Body() required String body,
  });

  /// The mailboxes of the company, the default one first.
  @GET('/api/v1/helpdesk/mailboxes')
  Future<List<Mailbox>> listMailboxes();

  @POST('/api/v1/helpdesk/mailboxes')
  Future<Mailbox> createMailbox({
    @Body() required MailboxInput body,
  });

  @PUT('/api/v1/helpdesk/mailboxes/{id}')
  Future<Mailbox> updateMailbox({
    @Path('id') required String id,
    @Body() required MailboxInput body,
  });

  /// Removes a mailbox. Its tickets and e-mails stay; replies on them then leave through the.
  /// default mailbox.
  @DELETE('/api/v1/helpdesk/mailboxes/{id}')
  Future<void> deleteMailbox({
    @Path('id') required String id,
  });

  /// The helpdesk report for a period. Response and resolution times are in business time when the.
  /// ticket's own calendar (its team's, else the company's) is on (see `basis`). Days are the.
  /// company's local days.
  ///
  /// [from] - First day (inclusive), `YYYY-MM-DD`. Default: 29 days before `to`.
  ///
  /// [to] - Last day (inclusive). Default: today.
  ///
  /// [group] - `day` (default) or `week` (weeks start on Monday).
  @GET('/api/v1/helpdesk/reports')
  Future<Report> getReport({
    @Query('from') DateTime? from,
    @Query('to') DateTime? to,
    @Query('team_id') String? teamId,
    @Query('owner_id') String? ownerId,
    @Query('category') String? category,
    @Query('group') String? group,
  });

  /// One table of the report as a CSV file.
  ///
  /// [table] - volume | backlog_status | backlog_priority | backlog_team | backlog_owner | times | sla |.
  /// breaches_by_team | top_categories | top_tags | time_by_user.
  @GET('/api/v1/helpdesk/reports/export')
  Future<String> exportReport({
    @Query('table') required String table,
    @Query('from') DateTime? from,
    @Query('to') DateTime? to,
    @Query('team_id') String? teamId,
    @Query('owner_id') String? ownerId,
    @Query('category') String? category,
    @Query('group') String? group,
  });

  @GET('/api/v1/helpdesk/settings')
  Future<HelpdeskSettings> getSettings();

  @PUT('/api/v1/helpdesk/settings')
  Future<HelpdeskSettings> putSettings({
    @Body() required SettingsInput body,
  });

  @GET('/api/v1/helpdesk/sla-notices')
  Future<SlaNoticeSettings> getSlaNotices();

  /// Replaces the rules. Tickets that were created earlier are not acknowledged afterwards; a breach.
  /// notice can still go out for an open ticket that is late when its rule is switched on.
  @PUT('/api/v1/helpdesk/sla-notices')
  Future<SlaNoticeSettings> putSlaNotices({
    @Body() required SlaNoticeSettings body,
  });

  @GET('/api/v1/helpdesk/sla-policies')
  Future<List<SlaPolicy>> getPolicies();

  /// Replaces the windows for the given priorities. Open tickets get new due times.
  @PUT('/api/v1/helpdesk/sla-policies')
  Future<List<SlaPolicy>> putPolicies({
    @Body() required SlaPoliciesInput body,
  });

  /// All tags in use at this company, for filters and suggestions.
  @GET('/api/v1/helpdesk/tags')
  Future<List<TagCount>> listTags();

  @GET('/api/v1/helpdesk/teams')
  Future<List<Team>> listTeams();

  @POST('/api/v1/helpdesk/teams')
  Future<Team> createTeam({
    @Body() required TeamInput body,
  });

  @PUT('/api/v1/helpdesk/teams/{id}')
  Future<Team> updateTeam({
    @Path('id') required String id,
    @Body() required TeamInput body,
  });

  /// [q] - Searches code, name and texts.
  @GET('/api/v1/prepared-answers')
  Future<List<PreparedAnswer>> listAnswers({
    @Query('q') String? q,
    @Query('active') bool? active,
  });

  @POST('/api/v1/prepared-answers')
  Future<PreparedAnswer> createAnswer({
    @Body() required PreparedAnswerInput body,
  });

  /// Placeholders that can be used in prepared answers, e.g. `{{quotation.number}}`.
  @GET('/api/v1/prepared-answers/placeholders')
  Future<List<String>> placeholders();

  @PUT('/api/v1/prepared-answers/{id}')
  Future<PreparedAnswer> updateAnswer({
    @Path('id') required String id,
    @Body() required PreparedAnswerInput body,
  });

  /// [q] - Searches number, subject, contact and customer.
  ///
  /// [status] - A status, or `active` for everything not closed.
  ///
  /// [owner] - `me` for my tickets, `none` for unassigned, or a user id.
  ///
  /// [teamId] - Tickets in this team.
  ///
  /// [mine] - Tickets that are mine: I own them, or nobody owns them and they are in one of my teams.
  ///
  /// [unassigned] - Tickets with neither an owner nor a team.
  ///
  /// [sla] - `breached` or `at_risk` (under 25 % of a window left).
  ///
  /// [tag] - Tickets with this tag.
  ///
  /// [unread] - Only tickets that are unread for me.
  ///
  /// [watching] - Only tickets I follow.
  ///
  /// [escalated] - Only tickets that were escalated by hand.
  @GET('/api/v1/tickets')
  Future<TicketPage> listTickets({
    @Query('q') String? q,
    @Query('status') String? status,
    @Query('owner') String? owner,
    @Query('customer_id') String? customerId,
    @Query('category') String? category,
    @Query('team_id') String? teamId,
    @Query('mine') bool? mine,
    @Query('unassigned') bool? unassigned,
    @Query('sla') String? sla,
    @Query('tag') String? tag,
    @Query('unread') bool? unread,
    @Query('watching') bool? watching,
    @Query('escalated') bool? escalated,
    @Query('limit') int? limit,
    @Query('offset') int? offset,
  });

  @POST('/api/v1/tickets')
  Future<TicketDetail> createTicket({
    @Body() required NewTicketInput body,
  });

  /// Production asks a question about an order. It becomes an internal ticket for the salesperson,.
  /// in the customer's language, so they can ask the customer and report back in a note.
  @POST('/api/v1/tickets/production-question')
  Future<TicketDetail> productionQuestion({
    @Body() required ProductionQuestionInput body,
  });

  @GET('/api/v1/tickets/{id}')
  Future<TicketDetail> getTicket({
    @Path('id') required String id,
  });

  @PUT('/api/v1/tickets/{id}')
  Future<TicketDetail> updateTicket({
    @Path('id') required String id,
    @Body() required TicketInput body,
  });

  /// Assigns a ticket to a team and/or an owner.
  @PUT('/api/v1/tickets/{id}/assignment')
  Future<TicketDetail> assign({
    @Path('id') required String id,
    @Body() required AssignmentInput body,
  });

  /// Uploads a file to the ticket: the request body is the file itself (JPEG, PNG, WebP or PDF,.
  /// at most 12 MB). Attach it to a note or reply by passing its id in `attachment_ids`.
  ///
  /// [filename] - The original file name.
  ///
  /// [clientId] - A client-chosen id: uploading the same id again returns the first upload (safe retries).
  @POST('/api/v1/tickets/{id}/attachments')
  Future<FileInfo> uploadTicketAttachment({
    @Path('id') required String id,
    @Body() required String body,
    @Query('filename') String? filename,
    @Query('client_id') String? clientId,
  });

  /// The file itself, as a download.
  @GET('/api/v1/tickets/{id}/attachments/{file_id}')
  Future<String> getTicketAttachment({
    @Path('id') required String id,
    @Path('file_id') required String fileId,
  });

  /// The customer confirmed the linked quotation: convert it into a sales order.
  /// If the customer asked for changes, revise the quotation first and link the new revision.
  @POST('/api/v1/tickets/{id}/convert')
  Future<TicketDetail> convert({
    @Path('id') required String id,
    @Body() required ConvertTicketInput body,
  });

  /// Hands the ticket over to a colleague with an optional internal comment. The previous owner.
  /// and the caller become watchers; the new owner is told by mail, comment included.
  @POST('/api/v1/tickets/{id}/delegate')
  Future<TicketDetail> delegate({
    @Path('id') required String id,
    @Body() required DelegateInput body,
  });

  /// Escalates a ticket by hand: records who and why, optionally raises the priority one step and.
  /// tells the target (a person; or the leads of a team; or, without a target, the leads of the.
  /// ticket's team, else its members, else the administrators). The caller becomes a watcher.
  @POST('/api/v1/tickets/{id}/escalate')
  Future<TicketDetail> escalate({
    @Path('id') required String id,
    @Body() required EscalateInput body,
  });

  /// The activity timeline: events and messages (customer and colleagues, internal notes.
  /// included), oldest first. Internal: never shown to customers.
  @GET('/api/v1/tickets/{id}/events')
  Future<List<TimelineItem>> timeline({
    @Path('id') required String id,
  });

  /// Turns the ticket into a sales lead: creates an opportunity for its customer and links it.
  @POST('/api/v1/tickets/{id}/lead')
  Future<TicketDetail> createLead({
    @Path('id') required String id,
    @Body() required LeadInput body,
  });

  /// Merges this ticket into another ticket of the same customer. Articles (with their.
  /// attachments), tags and time entries move to the target; this ticket is closed with a note.
  /// and points at the target. A merge cannot be undone. Returns the target.
  @POST('/api/v1/tickets/{id}/merge')
  Future<TicketDetail> merge({
    @Path('id') required String id,
    @Body() required MergeInput body,
  });

  /// Adds an internal note: never sent to the customer.
  @POST('/api/v1/tickets/{id}/notes')
  Future<TicketDetail> addNote({
    @Path('id') required String id,
    @Body() required NoteInput body,
  });

  /// Fills in a prepared answer for a ticket, in the ticket's language. Nothing is sent.
  @POST('/api/v1/tickets/{id}/prepared-answers/{answer_id}/render')
  Future<RenderedAnswer> renderAnswer({
    @Path('id') required String id,
    @Path('answer_id') required String answerId,
  });

  /// Colleagues (not the caller) active on the ticket during the last 60 seconds.
  @GET('/api/v1/tickets/{id}/presence')
  Future<List<PresenceEntry>> presenceList({
    @Path('id') required String id,
  });

  /// Heartbeat: "I am viewing / replying to this ticket". Returns who else is active, so one call.
  /// per beat is enough. Advisory only: nothing is locked.
  @POST('/api/v1/tickets/{id}/presence')
  Future<List<PresenceEntry>> presenceBeat({
    @Path('id') required String id,
    @Body() required PresenceInput body,
  });

  /// Marks the ticket as read by the caller (call it when the ticket was opened and shown).
  @POST('/api/v1/tickets/{id}/read')
  Future<void> markRead({
    @Path('id') required String id,
  });

  /// Queues an e-mail to the customer. The worker sends it; delivery status shows on the article.
  @POST('/api/v1/tickets/{id}/replies')
  Future<TicketDetail> reply({
    @Path('id') required String id,
    @Body() required ReplyInput body,
  });

  /// Moves the selected messages, with their attachments, into a new ticket for the same customer.
  /// and contact. The new ticket starts open with its own service level clock, in the same team and.
  /// with the same owner; both tickets get a note and an audit event. A split cannot be undone.
  /// (merge can join tickets again). Returns the new ticket.
  @POST('/api/v1/tickets/{id}/split')
  Future<TicketDetail> splitTicket({
    @Path('id') required String id,
    @Body() required SplitInput body,
  });

  @POST('/api/v1/tickets/{id}/tags')
  Future<TicketDetail> addTag({
    @Path('id') required String id,
    @Body() required TagInput body,
  });

  @DELETE('/api/v1/tickets/{id}/tags/{tag}')
  Future<TicketDetail> removeTag({
    @Path('id') required String id,
    @Path('tag') required String tag,
  });

  @GET('/api/v1/tickets/{id}/time-entries')
  Future<TimeEntries> listTime({
    @Path('id') required String id,
  });

  @POST('/api/v1/tickets/{id}/time-entries')
  Future<TimeEntries> addTime({
    @Path('id') required String id,
    @Body() required TimeEntryInput body,
  });

  /// Removes an entry: one's own, or any with the helpdesk admin permission.
  @DELETE('/api/v1/tickets/{id}/time-entries/{entry_id}')
  Future<TimeEntries> deleteTime({
    @Path('id') required String id,
    @Path('entry_id') required String entryId,
  });

  /// Follow the ticket yourself.
  @PUT('/api/v1/tickets/{id}/watch')
  Future<List<Watcher>> watch({
    @Path('id') required String id,
  });

  /// Stop following the ticket. Replying to it later makes you a watcher again.
  @DELETE('/api/v1/tickets/{id}/watch')
  Future<List<Watcher>> unwatch({
    @Path('id') required String id,
  });

  /// Adds a colleague as a watcher.
  @POST('/api/v1/tickets/{id}/watchers')
  Future<List<Watcher>> addWatcher({
    @Path('id') required String id,
    @Body() required WatcherInput body,
  });
}
