import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/actions.dart';
import '../../shared/format.dart';
import '../../shared/app_icons.dart';

/// "2d 3h", "1h 30m", "45m": how long, language independent.
String slaDuration(int minutes) {
  final m = minutes.abs();
  if (m >= 2880) return '${m ~/ 1440}d ${(m % 1440) ~/ 60}h';
  if (m >= 60) return '${m ~/ 60}h ${m % 60}m';
  return '${m}m';
}

Color slaColor(BuildContext context, String state) => switch (state) {
  'breached' => Colors.red.shade700,
  'at_risk' => Colors.orange.shade800,
  'on_time' => Colors.green.shade700,
  _ => Theme.of(context).colorScheme.outline,
};

String slaStateLabel(AppLocalizations l, String state) => switch (state) {
  'breached' => l.slaBreached,
  'at_risk' => l.slaAtRisk,
  'on_time' => l.slaOnTime,
  _ => l.slaNone,
};

/// What is left for the target that matters most: the open one that runs out first.
String slaSummary(AppLocalizations l, TicketSla sla) {
  final open =
      [
          sla.firstResponse,
          sla.resolution,
        ].where((t) => t.dueAt != null && t.minutesRemaining != null).toList()
        ..sort((a, b) => a.minutesRemaining!.compareTo(b.minutesRemaining!));
  final label = slaStateLabel(l, sla.state);
  if (sla.state == 'none' || open.isEmpty) return label;
  final left = open.first.minutesRemaining!;
  final time = left < 0
      ? l.slaOverdue(slaDuration(left))
      : l.slaLeft(slaDuration(left));
  return '$label · $time';
}

/// A coloured dot with the state (and, while open, the time left) of a ticket's SLA.
class SlaBadge extends StatelessWidget {
  const SlaBadge({super.key, required this.sla, this.compact = false});
  final TicketSla sla;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final color = slaColor(context, sla.state);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          sla.paused ? AppIcons.pauseCircle : AppIcons.circle,
          size: 12,
          color: color,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            compact ? slaStateLabel(l, sla.state) : slaSummary(l, sla),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color),
          ),
        ),
      ],
    );
  }
}

/// The two SLA targets of a ticket with their due times.
class SlaSection extends StatelessWidget {
  const SlaSection({super.key, required this.sla});
  final TicketSla sla;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    Widget row(String label, TargetState t) {
      final String text;
      if (t.dueAt == null) {
        text = l.slaNone;
      } else if (t.metAt != null) {
        text =
            '${t.breached ? l.slaBreached : l.slaMet} · ${l.slaDue(date(t.dueAt!))}';
      } else {
        final left = t.minutesRemaining ?? 0;
        text =
            '${left < 0 ? l.slaOverdue(slaDuration(left)) : l.slaLeft(slaDuration(left))} · ${l.slaDue(date(t.dueAt!))}';
      }
      final color = t.breached
          ? Colors.red.shade700
          : t.atRisk
          ? Colors.orange.shade800
          : null;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(flex: 2, child: Text(label)),
            Expanded(
              flex: 3,
              child: Text(
                text,
                textAlign: TextAlign.end,
                style: TextStyle(color: color),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      key: const ValueKey('sla-section'),
      children: [
        Row(
          children: [
            Text(l.sla, style: theme.textTheme.titleSmall),
            const SizedBox(width: 12),
            Expanded(child: SlaBadge(sla: sla, compact: true)),
          ],
        ),
        const SizedBox(height: 4),
        row(l.slaFirstResponse, sla.firstResponse),
        row(l.slaResolution, sla.resolution),
        if (sla.paused)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(l.slaPaused, style: theme.textTheme.bodySmall),
          ),
      ],
    );
  }
}

/// Free-form tags of a ticket.
class TagsSection extends ConsumerStatefulWidget {
  const TagsSection({
    super.key,
    required this.ticketId,
    required this.tags,
    required this.canWrite,
    required this.onChanged,
  });
  final String ticketId;
  final List<String> tags;
  final bool canWrite;
  final ValueChanged<TicketDetail> onChanged;

  @override
  ConsumerState<TagsSection> createState() => _TagsSectionState();
}

class _TagsSectionState extends ConsumerState<TagsSection> {
  final _new = TextEditingController();

  @override
  void dispose() {
    _new.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final tag = _new.text.trim();
    if (tag.isEmpty) return;
    final ok = await runAction(context, () async {
      widget.onChanged(
        await ref
            .read(apiProvider)
            .helpdesk
            .addTag(
              id: widget.ticketId,
              body: TagInput(tag: tag),
            ),
      );
    });
    if (ok) _new.clear();
  }

  Future<void> _remove(String tag) => runAction(context, () async {
    widget.onChanged(
      await ref
          .read(apiProvider)
          .helpdesk
          .removeTag(id: widget.ticketId, tag: tag),
    );
  });

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.tags, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final t in widget.tags)
              InputChip(
                key: ValueKey('tag-$t'),
                label: Text(t),
                onDeleted: widget.canWrite ? () => _remove(t) : null,
              ),
          ],
        ),
        if (widget.canWrite)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('new-tag'),
                    controller: _new,
                    decoration: InputDecoration(hintText: l.addTag),
                    onSubmitted: (_) => _add(),
                  ),
                ),
                IconButton(
                  tooltip: context.l10n.add,
                  onPressed: _add,
                  icon: const Icon(AppIcons.add),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Time entries of a ticket with their total.
class TimeSection extends ConsumerStatefulWidget {
  const TimeSection({
    super.key,
    required this.ticketId,
    required this.canWrite,
  });
  final String ticketId;
  final bool canWrite;

  @override
  ConsumerState<TimeSection> createState() => _TimeSectionState();
}

class _TimeSectionState extends ConsumerState<TimeSection> {
  TimeEntries? _entries;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final e = await ref
          .read(apiProvider)
          .helpdesk
          .listTime(id: widget.ticketId);
      if (mounted) setState(() => _entries = e);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  Future<void> _log() async {
    final input = await showDialog<TimeEntryInput>(
      context: context,
      builder: (_) => const _TimeDialog(),
    );
    if (input == null || !mounted) return;
    await runAction(context, () async {
      final e = await ref
          .read(apiProvider)
          .helpdesk
          .addTime(id: widget.ticketId, body: input);
      if (mounted) setState(() => _entries = e);
    });
  }

  Future<void> _delete(TimeEntry entry) => runAction(context, () async {
    final e = await ref
        .read(apiProvider)
        .helpdesk
        .deleteTime(id: widget.ticketId, entryId: entry.id);
    if (mounted) setState(() => _entries = e);
  });

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final e = _entries;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      key: const ValueKey('time-section'),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l.timeTracking,
                style: theme.textTheme.titleSmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (widget.canWrite)
              TextButton.icon(
                key: const ValueKey('log-time'),
                onPressed: _log,
                icon: const Icon(AppIcons.timer),
                label: Text(l.logTime),
              ),
          ],
        ),
        if (_error != null) Text(_error!),
        if (e != null && e.items.isEmpty)
          Text(l.noTimeEntries, style: theme.textTheme.bodySmall),
        if (e != null && e.items.isNotEmpty) ...[
          Text(
            l.timeTotal(
              minutesText(e.totalMinutes),
              minutesText(e.billableMinutes),
            ),
            key: const ValueKey('time-total'),
            style: theme.textTheme.bodyMedium,
          ),
          for (final x in e.items)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                '${minutesText(x.minutes)}${x.billable ? ' · ${l.billable}' : ''}'
                '${x.note.isEmpty ? '' : ' · ${x.note}'}',
              ),
              subtitle: Text('${x.userName} · ${date(x.createdAt)}'),
              trailing: widget.canWrite
                  ? IconButton(
                      tooltip: l.remove,
                      icon: const Icon(AppIcons.delete, size: 18),
                      onPressed: () => _delete(x),
                    )
                  : null,
            ),
        ],
      ],
    );
  }
}

class _TimeDialog extends StatefulWidget {
  const _TimeDialog();

  @override
  State<_TimeDialog> createState() => _TimeDialogState();
}

class _TimeDialogState extends State<_TimeDialog> {
  final _minutes = TextEditingController();
  final _note = TextEditingController();
  bool _billable = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final minutes = int.tryParse(_minutes.text.trim());
    return AlertDialog(
      title: Text(l.logTime),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('time-minutes'),
              controller: _minutes,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: l.minutes),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _note,
              decoration: InputDecoration(labelText: l.timeNote),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.billable),
              value: _billable,
              onChanged: (v) => setState(() => _billable = v ?? false),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: minutes == null || minutes < 1 || minutes > 1440
              ? null
              : () => Navigator.pop(
                  context,
                  TimeEntryInput(
                    minutes: minutes,
                    note: _note.text.trim(),
                    billable: _billable,
                  ),
                ),
          child: Text(l.save),
        ),
      ],
    );
  }
}

/// The customer's rating of how the ticket was handled, if they gave one.
class CsatSection extends StatelessWidget {
  const CsatSection({super.key, required this.ticket});
  final Ticket ticket;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final rating = ticket.csatRating;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      key: const ValueKey('csat-section'),
      children: [
        Text(l.csatTitle, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        if (rating == null)
          Text(l.csatNone, style: theme.textTheme.bodySmall)
        else
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(
                rating == 'good'
                    ? AppIcons.sentimentSatisfiedAlt
                    : AppIcons.sentimentDissatisfied,
                color: rating == 'good'
                    ? Colors.green.shade700
                    : Colors.red.shade700,
              ),
              Text(rating == 'good' ? l.csatGood : l.csatBad),
              if (ticket.csatRatedAt != null) ...[
                Text(
                  date(ticket.csatRatedAt!),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
        if ((ticket.csatComment ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: SelectableText('"${ticket.csatComment}"'),
          ),
      ],
    );
  }
}

/// Merges the ticket into another open ticket of the same customer. Returns the target.
Future<TicketDetail?> showMergeDialog(
  BuildContext context, {
  required Ticket ticket,
}) => showDialog<TicketDetail>(
  context: context,
  builder: (_) => _MergeDialog(ticket: ticket),
);

class _MergeDialog extends ConsumerStatefulWidget {
  const _MergeDialog({required this.ticket});
  final Ticket ticket;

  @override
  ConsumerState<_MergeDialog> createState() => _MergeDialogState();
}

class _MergeDialogState extends ConsumerState<_MergeDialog> {
  late final Future<List<Ticket>> _candidates = ref
      .read(apiProvider)
      .helpdesk
      .listTickets(
        customerId: widget.ticket.customerId,
        status: 'active',
        limit: 100,
      )
      .then(
        (p) => [
          for (final t in p.items)
            if (t.id != widget.ticket.id) t,
        ],
      );
  String? _target;
  String? _error;
  bool _busy = false;

  Future<void> _merge() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final d = await ref
          .read(apiProvider)
          .helpdesk
          .merge(
            id: widget.ticket.id,
            body: MergeInput(targetId: _target!),
          );
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
    return AlertDialog(
      title: Text(
        '${l.mergeTicket.replaceAll('…', '')} · ${widget.ticket.number}',
      ),
      content: SizedBox(
        width: 520,
        height: 380,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.mergeHelp),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<List<Ticket>>(
                future: _candidates,
                builder: (context, snap) {
                  if (snap.hasError) return Text(errorMessage(snap.error!));
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final list = snap.data!;
                  if (list.isEmpty) return Text(l.mergeNoCandidates);
                  return ListView(
                    children: [
                      for (final t in list)
                        ListTile(
                          key: ValueKey('merge-${t.id}'),
                          dense: true,
                          selected: _target == t.id,
                          selectedTileColor: Theme.of(context)
                              .colorScheme
                              .primaryContainer,
                          title: Text('${t.number} · ${t.subject}'),
                          subtitle: Text(l.ticketStatus(t.status)),
                          trailing: _target == t.id
                              ? const Icon(AppIcons.check)
                              : null,
                          onTap: () => setState(() => _target = t.id),
                        ),
                    ],
                  );
                },
              ),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('confirm-merge'),
          onPressed: _target == null || _busy ? null : _merge,
          child: Text(l.mergeAction),
        ),
      ],
    );
  }
}
