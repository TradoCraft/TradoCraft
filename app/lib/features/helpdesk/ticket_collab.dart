import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/actions.dart';
import 'ticket_screen.dart' show teamsProvider, usersProvider;
import '../../shared/app_icons.dart';

/// Collaboration widgets of the ticket screen: escalate and hand-over dialogs, watchers, the
/// activity timeline, the "seen by" line and the presence banner (ADR 0023).

// ---------------------------------------------------------------------------------------------
// Escalate and delegate: one dialog pattern (target picker + comment)
// ---------------------------------------------------------------------------------------------

/// Escalates the ticket: a reason (required), an optional person or team, and optionally a
/// higher priority. Returns the updated ticket, or null when cancelled.
Future<TicketDetail?> showEscalateDialog(
  BuildContext context, {
  required String ticketId,
}) => showDialog<TicketDetail>(
  context: context,
  builder: (_) => _TargetCommentDialog(ticketId: ticketId, escalate: true),
);

/// Hands the ticket over to a colleague with an optional internal comment.
Future<TicketDetail?> showDelegateDialog(
  BuildContext context, {
  required String ticketId,
  String? currentOwnerId,
}) => showDialog<TicketDetail>(
  context: context,
  builder: (_) => _TargetCommentDialog(
    ticketId: ticketId,
    escalate: false,
    currentOwnerId: currentOwnerId,
  ),
);

class _TargetCommentDialog extends ConsumerStatefulWidget {
  const _TargetCommentDialog({
    required this.ticketId,
    required this.escalate,
    this.currentOwnerId,
  });
  final String ticketId;
  final bool escalate;
  final String? currentOwnerId;

  @override
  ConsumerState<_TargetCommentDialog> createState() =>
      _TargetCommentDialogState();
}

class _TargetCommentDialogState extends ConsumerState<_TargetCommentDialog> {
  final _text = TextEditingController();

  /// `u:<user id>` or `t:<team id>`; null = no explicit target.
  String? _target;
  bool _raise = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _valid =>
      widget.escalate ? _text.text.trim().isNotEmpty : _target != null;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = ref.read(apiProvider).helpdesk;
      final target = _target;
      final id = target?.substring(2);
      final TicketDetail d;
      if (widget.escalate) {
        d = await api.escalate(
          id: widget.ticketId,
          body: EscalateInput(
            reason: _text.text.trim(),
            toUserId: target?.startsWith('u:') == true ? id : null,
            toTeamId: target?.startsWith('t:') == true ? id : null,
            raisePriority: _raise,
          ),
        );
      } else {
        d = await api.delegate(
          id: widget.ticketId,
          body: DelegateInput(
            toUserId: id!,
            comment: _text.text.trim().isEmpty ? null : _text.text.trim(),
          ),
        );
      }
      if (mounted) Navigator.pop(context, d);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = errorMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final users = ref.watch(usersProvider).value ?? const <CompanyUser>[];
    final teams = (ref.watch(teamsProvider).value ?? const <Team>[])
        .where((t) => t.active)
        .toList();
    final me = ref.watch(meProvider).value?.userId;
    final people = [
      for (final u in users)
        if (widget.escalate ? u.id != me : u.id != widget.currentOwnerId) u,
    ];
    return AlertDialog(
      title: Text(
        widget.escalate ? l.collabEscalateTitle : l.collabDelegateTitle,
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String?>(
                key: ValueKey('target-${users.length}-${teams.length}'),
                isExpanded: true,
                initialValue: _target,
                decoration: InputDecoration(
                  labelText: widget.escalate
                      ? l.collabEscalateTo
                      : l.collabHandOverTo,
                ),
                items: [
                  if (widget.escalate)
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(l.collabNoTarget),
                    ),
                  for (final u in people)
                    DropdownMenuItem<String?>(
                      value: 'u:${u.id}',
                      child: Text('${l.collabPerson}: ${u.displayName}'),
                    ),
                  if (widget.escalate)
                    for (final t in teams)
                      DropdownMenuItem<String?>(
                        value: 't:${t.id}',
                        child: Text('${l.collabTeam}: ${t.name}'),
                      ),
                ],
                onChanged: (v) => setState(() => _target = v),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('collab-text'),
                controller: _text,
                minLines: 3,
                maxLines: 6,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: widget.escalate
                      ? l.collabReasonRequired
                      : l.collabCommentOptional,
                  helperText: l.collabInternalHint,
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (widget.escalate)
                CheckboxListTile(
                  key: const ValueKey('collab-raise'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _raise,
                  title: Text(l.collabRaisePriority),
                  onChanged: (v) => setState(() => _raise = v ?? false),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('collab-submit'),
          onPressed: _busy || !_valid ? null : _submit,
          child: Text(widget.escalate ? l.collabEscalate : l.collabDelegate),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Watchers
// ---------------------------------------------------------------------------------------------

/// The Watch / Stop watching toggle and the people who follow the ticket.
class WatchersSection extends ConsumerWidget {
  const WatchersSection({
    super.key,
    required this.ticketId,
    required this.watchers,
    required this.canWrite,
    required this.onChanged,
  });
  final String ticketId;
  final List<Watcher> watchers;
  final bool canWrite;
  final ValueChanged<List<Watcher>> onChanged;

  Future<void> _toggle(BuildContext context, WidgetRef ref, bool mine) =>
      runAction(context, () async {
        final api = ref.read(apiProvider).helpdesk;
        onChanged(
          mine
              ? await api.unwatch(id: ticketId)
              : await api.watch(id: ticketId),
        );
      });

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final users = ref.read(usersProvider).value ?? const <CompanyUser>[];
    final candidates = [
      for (final u in users)
        if (!watchers.any((w) => w.userId == u.id)) u,
    ];
    final picked = await showDialog<CompanyUser>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(context.l10n.collabAddWatcher),
        children: [
          for (final u in candidates)
            SimpleDialogOption(
              key: ValueKey('watcher-option-${u.id}'),
              onPressed: () => Navigator.pop(context, u),
              child: Text(u.displayName),
            ),
        ],
      ),
    );
    if (picked == null || !context.mounted) return;
    await runAction(context, () async {
      onChanged(
        await ref
            .read(apiProvider)
            .helpdesk
            .addWatcher(
              id: ticketId,
              body: WatcherInput(userId: picked.id),
            ),
      );
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final me = ref.watch(meProvider).value?.userId;
    final mine = watchers.any((w) => w.userId == me);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l.collabWatchers,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            OutlinedButton.icon(
              key: const ValueKey('watch-toggle'),
              onPressed: () => _toggle(context, ref, mine),
              icon: Icon(mine ? AppIcons.visibilityOff : AppIcons.visibility),
              label: Text(mine ? l.collabUnwatch : l.collabWatch),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (watchers.isEmpty)
          Text(l.collabNoWatchers, style: Theme.of(context).textTheme.bodySmall)
        else
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final w in watchers)
                Chip(
                  key: ValueKey('watcher-${w.userId}'),
                  avatar: const Icon(AppIcons.visibility, size: 16),
                  label: Text(w.userName),
                ),
            ],
          ),
        if (canWrite)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('watcher-add'),
              onPressed: () => _add(context, ref),
              icon: const Icon(AppIcons.personAddAlt),
              label: Text(l.collabAddWatcher),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Seen by
// ---------------------------------------------------------------------------------------------

/// "Seen by Jo 14:02, Els 13:50" (most recent first, at most five names).
class SeenByLine extends StatelessWidget {
  const SeenByLine({super.key, required this.readers});
  final List<Reader> readers;

  @override
  Widget build(BuildContext context) {
    if (readers.isEmpty) return const SizedBox.shrink();
    final time = DateFormat.Hm();
    final text = [
      for (final r in readers.take(5))
        '${r.userName} ${time.format(r.lastReadAt.toLocal())}',
    ].join(', ');
    return Text(
      context.l10n.collabSeenBy(text),
      key: const ValueKey('seen-by'),
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Activity timeline
// ---------------------------------------------------------------------------------------------

/// What a timeline line says, in the user's language.
String timelineText(AppLocalizations l, TimelineItem e) {
  final actor = e.actorName ?? l.collabSystem;
  String status(String? s) => s == null ? '' : l.ticketStatus(s);
  String priority(String? s) => s == null ? '' : l.ticketPriority(s);
  if (e.source == 'message') {
    return switch (e.kind) {
      'email_in' || 'portal_in' => l.collabMsgCustomer(actor),
      'email_out' => l.collabMsgReply(actor),
      'call_in' || 'call_out' => l.collabMsgCall(actor),
      _ => l.collabMsgNote(actor),
    };
  }
  return switch (e.kind) {
    'created' => l.collabEventCreated(actor),
    'assigned' when e.toValue == 'team' =>
      e.targetTeamName == null
          ? l.collabEventTeamCleared(actor)
          : l.collabEventTeam(actor, e.targetTeamName!),
    'assigned' =>
      e.targetUserName == null
          ? l.collabEventOwnerCleared(actor)
          : l.collabEventAssignedOwner(actor, e.targetUserName!),
    'delegated' => l.collabEventDelegated(actor, e.targetUserName ?? ''),
    'escalated' => l.collabEventEscalated(actor),
    'status' => l.collabEventStatus(
      actor,
      status(e.fromValue),
      status(e.toValue),
    ),
    'priority' => l.collabEventPriority(
      actor,
      priority(e.fromValue),
      priority(e.toValue),
    ),
    'merged' =>
      e.toValue != null
          ? l.collabEventMergedInto(actor, e.toValue!)
          : l.collabEventMergedFrom(actor, e.fromValue ?? ''),
    'tag_added' => l.collabEventTagAdded(actor, e.toValue ?? ''),
    'tag_removed' => l.collabEventTagRemoved(actor, e.toValue ?? ''),
    _ => actor,
  };
}

/// The ticket's activity, newest first. Reloads when [version] changes.
class ActivitySection extends ConsumerStatefulWidget {
  const ActivitySection({
    super.key,
    required this.ticketId,
    required this.version,
  });
  final String ticketId;

  /// Anything that changes when the ticket changes (e.g. its update time).
  final Object version;

  @override
  ConsumerState<ActivitySection> createState() => _ActivitySectionState();
}

class _ActivitySectionState extends ConsumerState<ActivitySection> {
  List<TimelineItem>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ActivitySection old) {
    super.didUpdateWidget(old);
    if (old.version != widget.version) _load();
  }

  Future<void> _load() async {
    try {
      final items = await ref
          .read(apiProvider)
          .helpdesk
          .timeline(id: widget.ticketId);
      if (mounted) {
        setState(() {
          _items = items.reversed.toList();
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final items = _items;
    final stamp = DateFormat('d MMM HH:mm');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.collabActivity, style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        if (_error != null)
          Text(_error!)
        else if (items == null)
          const LinearProgressIndicator()
        else if (items.isEmpty)
          Text(l.collabNoActivity, style: theme.textTheme.bodySmall)
        else
          for (final e in items)
            Padding(
              key: ValueKey('activity-${e.id}'),
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2, right: 8),
                    child: Icon(
                      _icon(e),
                      size: 16,
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(timelineText(l, e)),
                        if (e.comment.isNotEmpty)
                          Text(
                            e.comment,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        Text(
                          stamp.format(e.at.toLocal()),
                          style: theme.textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }

  IconData _icon(TimelineItem e) {
    if (e.source == 'message') {
      return switch (e.kind) {
        'email_out' => AppIcons.reply,
        'note' => AppIcons.lock,
        'call_in' || 'call_out' => AppIcons.phoneInTalk,
        _ => AppIcons.mail,
      };
    }
    return switch (e.kind) {
      'escalated' => AppIcons.trendingUp,
      'delegated' || 'assigned' => AppIcons.swapHoriz,
      'status' => AppIcons.flag,
      'priority' => AppIcons.priorityHigh,
      'merged' => AppIcons.mergeType,
      'tag_added' || 'tag_removed' => AppIcons.sell,
      _ => AppIcons.addCircle,
    };
  }
}

// ---------------------------------------------------------------------------------------------
// Presence
// ---------------------------------------------------------------------------------------------

/// "Jo is replying — coordinate before sending" (or, when nobody types, who is looking).
class PresenceBanner extends StatelessWidget {
  const PresenceBanner({super.key, required this.others});
  final List<PresenceEntry> others;

  @override
  Widget build(BuildContext context) {
    if (others.isEmpty) return const SizedBox.shrink();
    final l = context.l10n;
    final theme = Theme.of(context);
    final replying = others.where((o) => o.mode == 'replying').toList();
    final shown = replying.isNotEmpty ? replying : others;
    final names = shown.map((o) => o.userName).join(', ');
    final text = replying.isNotEmpty
        ? l.collabReplying(replying.length, names)
        : l.collabViewing(shown.length, names);
    return Container(
      key: const ValueKey('presence-banner'),
      color: replying.isNotEmpty
          ? Colors.amber.shade100
          : theme.colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(
            replying.isNotEmpty ? AppIcons.editNote : AppIcons.visibility,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

/// Asks whether to send although colleagues are replying. True = send.
Future<bool> confirmSendWhileOthersReply(
  BuildContext context,
  List<PresenceEntry> replying,
) async {
  final l = context.l10n;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      content: Text(
        l.collabConfirmSend(
          replying.length,
          replying.map((o) => o.userName).join(', '),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('send-anyway'),
          onPressed: () => Navigator.pop(context, true),
          child: Text(l.collabSendAnyway),
        ),
      ],
    ),
  );
  return ok == true;
}
