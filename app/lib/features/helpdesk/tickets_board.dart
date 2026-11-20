import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/api.dart';
import '../../core/theme/tokens.dart';
import '../../framework/views/kanban/kanban_config.dart';
import '../../framework/views/kanban/kanban_controller.dart';
import '../../framework/views/kanban/kanban_view.dart';
import '../../l10n/l10n.dart';
import '../../shared/app_icons.dart';
import 'ticket_extras.dart';
import 'tickets_page.dart'
    show ChecklistProgressBadge, NewTicketDialog, ticketStatuses;

/// The tickets as a kanban board (ADR 0087): one column per status, cards moved by dragging or by
/// the menu on the card. A move is `POST /tickets/{id}/status`, so the automation rules, the SLA,
/// the timeline and the close gate behave as when the ticket screen saves a new status.
class TicketsBoard extends ConsumerStatefulWidget {
  const TicketsBoard({super.key});

  @override
  ConsumerState<TicketsBoard> createState() => _TicketsBoardState();
}

class _TicketsBoardState extends ConsumerState<TicketsBoard> {
  final _search = TextEditingController();
  String? _q;

  /// `me` | `none` | `all`, as on the list.
  String _owner = 'me';
  KanbanController<Ticket>? _controller;
  Locale? _locale;

  HelpdeskClient get _helpdesk => ref.read(apiProvider).helpdesk;

  @override
  void initState() {
    super.initState();
    // The user's rights arrive after the board is first built, and can change: the "+" follows
    // them. The loaded cards stay.
    ref.listenManual(meProvider, (_, _) {
      if (_controller == null || !mounted) return;
      _controller!.updateConfig(_config(context));
      setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = Localizations.localeOf(context);
    final controller = _controller;
    if (controller == null) {
      // Created once the localisations are available: the column titles are translated.
      final created = KanbanController(_config(context));
      _controller = created;
      _locale = locale;
      created.load();
    } else if (locale != _locale) {
      _locale = locale;
      controller.updateConfig(_config(context));
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _search.dispose();
    super.dispose();
  }

  KanbanConfig<Ticket> _config(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final canWrite =
        ref.read(meProvider).value?.permissions.contains('helpdesk.write') ??
        false;
    return KanbanConfig<Ticket>(
      columns: [
        for (final s in ticketStatuses)
          KanbanColumnDef(
            s,
            l.ticketStatus(s),
            color: switch (s) {
              'new' => scheme.primary,
              'pending_customer' || 'pending_internal' => Colors.amber.shade700,
              _ => null,
            },
          ),
      ],
      idOf: (t) => t.id,
      cardBuilder: (context, t) => _TicketCard(t),
      loadColumn: (status, offset, limit) async {
        final page = await _helpdesk.listTickets(
          q: _q,
          mine: _owner == 'me' ? true : null,
          unassigned: _owner == 'none' ? true : null,
          status: status,
          offset: offset,
          limit: limit,
        );
        return KanbanPage(page.items, page.total);
      },
      move: _move,
      onOpen: (t) async {
        await context.push<bool>('/helpdesk/${t.id}');
        if (mounted) _controller?.load();
      },
      // A status change runs the automation rules and recalculates the SLA: the card shows what
      // the server holds afterwards.
      reloadAfterMove: true,
      // A ticket is never created straight into the closed column.
      canCreateIn: (id) => id != 'closed',
      onCreate: canWrite ? _create : null,
    );
  }

  Future<MoveResult> _move(Ticket t, String status) async {
    if (status == 'closed') {
      // One drop must not close a ticket by accident: closing can send the customer a
      // satisfaction survey, which cannot be taken back.
      final l = context.l10n;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l.ticketsBoardCloseTitle),
          content: Text(l.ticketsBoardCloseBody(t.number)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
            ),
            FilledButton(
              key: const ValueKey('board-close-confirm'),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.ticketsBoardClose),
            ),
          ],
        ),
      );
      if (ok != true) return MoveResult.cancelled;
    }
    // No expected version: a board move is a status and nothing else, and a colleague's other
    // edits must not make it fail. The server refuses what it must (the close gate).
    await _helpdesk.changeTicketStatus(
      id: t.id,
      body: TicketStatusInput(status: status),
    );
    return MoveResult.moved;
  }

  /// The "+" of a column: the usual dialog for a call or visit, then the ticket is put in that
  /// column.
  Future<void> _create(String status) async {
    final created = await showDialog<TicketDetail>(
      context: context,
      builder: (_) => const NewTicketDialog(),
    );
    if (created == null || !mounted) return;
    if (created.ticket.status != status) {
      try {
        await _helpdesk.changeTicketStatus(
          id: created.ticket.id,
          body: TicketStatusInput(status: status),
        );
      } catch (e) {
        if (mounted) _controller?.error = errorMessage(e);
      }
    }
    if (mounted) await _controller?.load();
  }

  void _submit(String text) {
    final q = text.trim();
    _q = q.isEmpty ? null : q;
    _controller?.load();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final controller = _controller!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 0),
          child: Wrap(
            spacing: Space.md,
            runSpacing: Space.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 320,
                child: TextField(
                  key: const ValueKey('board-search'),
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: l.search,
                    prefixIcon: const Icon(AppIcons.search),
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: _submit,
                ),
              ),
              SegmentedButton<String>(
                key: const ValueKey('board-owner'),
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: 'me', label: Text(l.myTickets)),
                  ButtonSegment(value: 'none', label: Text(l.unassigned)),
                  ButtonSegment(value: 'all', label: Text(l.all)),
                ],
                selected: {_owner},
                onSelectionChanged: (s) {
                  setState(() => _owner = s.first);
                  controller.load();
                },
              ),
            ],
          ),
        ),
        Expanded(child: KanbanView<Ticket>(controller: controller)),
      ],
    );
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard(this.t);
  final Ticket t;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final who =
        t.customerName ??
        (t.contactName.isEmpty ? t.contactEmail : t.contactName);
    final hot = t.priority == 'urgent' || t.priority == 'high';
    return Semantics(
      label: '${t.number} ${t.subject}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(child: Text(t.number, style: muted)),
              if (hot) ...[
                const SizedBox(width: Space.sm),
                Text(
                  l.ticketPriority(t.priority),
                  key: ValueKey('ticket-priority-${t.id}'),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: t.priority == 'urgent'
                        ? scheme.error
                        : Colors.orange.shade800,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (t.escalatedAt != null) ...[
                const SizedBox(width: Space.xs),
                Icon(AppIcons.trendingUp, size: 14, color: Colors.red.shade700),
              ],
              if (t.unread) ...[
                const SizedBox(width: Space.xs),
                Icon(
                  AppIcons.circle,
                  key: ValueKey('ticket-unread-${t.id}'),
                  size: 8,
                  color: scheme.primary,
                ),
              ],
            ],
          ),
          Text(
            t.subject,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: t.unread ? FontWeight.w700 : FontWeight.w500,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (who.isNotEmpty)
            Text(
              who,
              style: muted,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: Space.xs),
          Row(
            children: [
              Flexible(child: SlaBadge(sla: t.sla, compact: true)),
              if (t.checklistTotal > 0) ...[
                const SizedBox(width: Space.sm),
                ChecklistProgressBadge(
                  done: t.checklistDone,
                  total: t.checklistTotal,
                ),
              ],
            ],
          ),
          if (t.ownerName != null)
            Text(
              t.ownerName!,
              style: muted,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}
