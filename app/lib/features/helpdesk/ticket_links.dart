import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/app_icons.dart';

/// The tickets linked to this one (A9): the bundle it belongs to or heads, related tickets and
/// duplicates, each with the state of the other ticket. Links show in both tickets; this card
/// loads them again whenever [refreshVersion] changes (a colleague changed a link).
class TicketLinksCard extends ConsumerStatefulWidget {
  const TicketLinksCard({
    super.key,
    required this.ticketId,
    required this.number,
    required this.canWrite,
    required this.canReply,
    this.refreshVersion = 0,
  });

  final String ticketId;
  final String number;
  final bool canWrite;
  final bool canReply;
  final int refreshVersion;

  @override
  ConsumerState<TicketLinksCard> createState() => _TicketLinksCardState();
}

class _TicketLinksCardState extends ConsumerState<TicketLinksCard> {
  TicketLinks? _links;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(TicketLinksCard old) {
    super.didUpdateWidget(old);
    if (old.refreshVersion != widget.refreshVersion) _load();
  }

  Future<void> _load() async {
    try {
      final links = await ref
          .read(apiProvider)
          .helpdesk
          .listLinks(id: widget.ticketId);
      if (mounted) {
        setState(() {
          _links = links;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  Future<void> _add() async {
    final links = await showDialog<TicketLinks>(
      context: context,
      builder: (_) =>
          _AddLinkDialog(ticketId: widget.ticketId, number: widget.number),
    );
    if (links != null && mounted) setState(() => _links = links);
  }

  Future<void> _remove(LinkedTicket t) async {
    try {
      final links = await ref
          .read(apiProvider)
          .helpdesk
          .removeLink(id: widget.ticketId, linkId: t.linkId);
      if (mounted) setState(() => _links = links);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(errorMessage(e))));
      }
    }
  }

  Future<void> _update(TicketLinks links) async {
    await showDialog<void>(
      context: context,
      builder: (_) =>
          _BundleUpdateDialog(ticketId: widget.ticketId, links: links),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final links = _links;
    final empty =
        links != null &&
        links.parent == null &&
        links.children.isEmpty &&
        links.related.isEmpty &&
        links.duplicateOf == null &&
        links.duplicates.isEmpty;
    return Column(
      key: const ValueKey('ticket-links'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // A wrapping header: the side panel is narrow and the button label long in some languages.
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(l.linksTitle, style: theme.textTheme.titleSmall),
            if (widget.canWrite)
              TextButton.icon(
                key: const ValueKey('add-link'),
                onPressed: _add,
                icon: const Icon(AppIcons.link, size: 18),
                label: Text(l.linksAdd),
              ),
          ],
        ),
        if (_error != null)
          Text(_error!, style: TextStyle(color: theme.colorScheme.error))
        else if (links == null)
          const Padding(
            padding: EdgeInsets.all(8),
            child: LinearProgressIndicator(),
          )
        else if (empty)
          Text(l.linksNone, style: theme.textTheme.bodySmall)
        else ...[
          if (links.parent != null)
            _Group(
              title: l.linksParent,
              members: [links.parent!],
              onRemove: widget.canWrite ? _remove : null,
            ),
          if (links.children.isNotEmpty)
            _Group(
              title: l.linksChildren,
              summary: l.linksBundleProgress(
                links.children.where((c) => _isOpen(c)).length,
                links.children.length,
              ),
              members: links.children,
              onRemove: widget.canWrite ? _remove : null,
              action: widget.canWrite
                  ? FilledButton.tonalIcon(
                      key: const ValueKey('bundle-update'),
                      onPressed: () => _update(links),
                      icon: const Icon(AppIcons.send, size: 18),
                      label: Text(l.bundleUpdate),
                    )
                  : null,
            ),
          if (links.related.isNotEmpty)
            _Group(
              title: l.linksRelated,
              members: links.related,
              onRemove: widget.canWrite ? _remove : null,
            ),
          if (links.duplicateOf != null)
            _Group(
              title: l.linksDuplicateOf,
              members: [links.duplicateOf!],
              onRemove: widget.canWrite ? _remove : null,
            ),
          if (links.duplicates.isNotEmpty)
            _Group(
              title: l.linksDuplicates,
              members: links.duplicates,
              onRemove: widget.canWrite ? _remove : null,
            ),
        ],
      ],
    );
  }
}

/// A bundled ticket still needs work unless it is closed or merged away.
bool _isOpen(LinkedTicket t) => t.status != 'closed' && !t.merged;

class _Group extends StatelessWidget {
  const _Group({
    required this.title,
    required this.members,
    this.summary,
    this.onRemove,
    this.action,
  });

  final String title;
  final String? summary;
  final List<LinkedTicket> members;
  final void Function(LinkedTicket)? onRemove;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            summary == null ? title : '$title · $summary',
            style: theme.textTheme.labelLarge,
          ),
          for (final t in members)
            ListTile(
              key: ValueKey('link-${t.ticketId}'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                '${t.number} · ${t.subject}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                [
                  t.merged ? l.linksMerged : l.ticketStatus(t.status),
                  if (t.customerName != null) t.customerName!,
                  if (t.ownerName != null) t.ownerName!,
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => context.push('/helpdesk/${t.ticketId}'),
              trailing: onRemove == null
                  ? null
                  : IconButton(
                      key: ValueKey('unlink-${t.ticketId}'),
                      tooltip: l.linksRemove,
                      icon: const Icon(AppIcons.linkOff, size: 18),
                      onPressed: () => onRemove!(t),
                    ),
            ),
          if (action != null)
            Align(alignment: Alignment.centerLeft, child: action),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Add a link
// ---------------------------------------------------------------------------------------------

class _AddLinkDialog extends ConsumerStatefulWidget {
  const _AddLinkDialog({required this.ticketId, required this.number});
  final String ticketId;
  final String number;

  @override
  ConsumerState<_AddLinkDialog> createState() => _AddLinkDialogState();
}

class _AddLinkDialogState extends ConsumerState<_AddLinkDialog> {
  final _search = TextEditingController();
  LinkRelation _relation = LinkRelation.related;
  List<Ticket>? _found;
  String? _target;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _find();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _find() async {
    try {
      final q = _search.text.trim();
      final page = await ref
          .read(apiProvider)
          .helpdesk
          .listTickets(q: q.isEmpty ? null : q, limit: 30);
      if (mounted) {
        setState(
          () => _found = [
            for (final t in page.items)
              if (t.id != widget.ticketId && t.mergedIntoId == null) t,
          ],
        );
      }
    } catch (e) {
      // Show the error instead of a spinner that never ends.
      if (mounted) {
        setState(() {
          _error = errorMessage(e);
          _found = const [];
        });
      }
    }
  }

  Future<void> _link() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final links = await ref
          .read(apiProvider)
          .helpdesk
          .addLink(
            id: widget.ticketId,
            body: LinkInput(targetId: _target!, relation: _relation),
          );
      if (mounted) Navigator.pop(context, links);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = errorMessage(e);
        });
      }
    }
  }

  String _relationLabel(LinkRelation r) {
    final l = context.l10n;
    return switch (r) {
      LinkRelation.child => l.linksRelationChild,
      LinkRelation.parent => l.linksRelationParent,
      LinkRelation.related => l.linksRelationRelated,
      LinkRelation.duplicateOf => l.linksRelationDuplicateOf,
      LinkRelation.duplicatedBy => l.linksRelationDuplicatedBy,
      LinkRelation.$unknown => '',
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final found = _found;
    return AlertDialog(
      title: Text('${l.linksAdd.replaceAll('…', '')} · ${widget.number}'),
      content: SizedBox(
        width: 520,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<LinkRelation>(
              key: const ValueKey('link-relation'),
              isExpanded: true,
              initialValue: _relation,
              items: [
                for (final r in LinkRelation.values)
                  if (r != LinkRelation.$unknown)
                    DropdownMenuItem(
                      value: r,
                      child: Text(
                        _relationLabel(r),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
              ],
              onChanged: (r) => setState(() => _relation = r ?? _relation),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('link-search'),
              controller: _search,
              decoration: InputDecoration(
                labelText: l.linksSearch,
                prefixIcon: const Icon(AppIcons.search),
              ),
              onSubmitted: (_) => _find(),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: found == null
                  ? const Center(child: CircularProgressIndicator())
                  : found.isEmpty
                  ? (_error == null ? Text(l.linksNoMatches) : const SizedBox())
                  : ListView(
                      children: [
                        for (final t in found)
                          ListTile(
                            key: ValueKey('pick-${t.id}'),
                            dense: true,
                            selected: _target == t.id,
                            selectedTileColor: Theme.of(context)
                                .colorScheme
                                .primaryContainer,
                            title: Text('${t.number} · ${t.subject}'),
                            subtitle: Text(
                              [
                                l.ticketStatus(t.status),
                                if (t.customerName != null) t.customerName!,
                              ].join(' · '),
                            ),
                            trailing: _target == t.id
                                ? const Icon(AppIcons.check)
                                : null,
                            onTap: () => setState(() => _target = t.id),
                          ),
                      ],
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
          key: const ValueKey('confirm-link'),
          onPressed: _target == null || _busy ? null : _link,
          child: Text(l.linksAddAction),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Bundle update: a reply, a note or a status for every ticket in the bundle, previewed first
// ---------------------------------------------------------------------------------------------

class _BundleUpdateDialog extends ConsumerStatefulWidget {
  const _BundleUpdateDialog({required this.ticketId, required this.links});
  final String ticketId;
  final TicketLinks links;

  @override
  ConsumerState<_BundleUpdateDialog> createState() =>
      _BundleUpdateDialogState();
}

const _bundleStatuses = [
  'open',
  'pending_customer',
  'pending_internal',
  'closed',
];

class _BundleUpdateDialogState extends ConsumerState<_BundleUpdateDialog> {
  final _body = TextEditingController();

  /// What the user picked; until then replying when allowed, else a note.
  MassAction? _chosen;
  MassAction get _action =>
      _chosen ?? (_canReply ? MassAction.reply : MassAction.note);
  bool get _canReply =>
      ref.read(meProvider).value?.permissions.contains('helpdesk.reply') ??
      false;
  String? _status;
  MassUpdateResult? _preview;
  MassUpdateResult? _done;

  /// Children left out of the update by the user after the preview.
  final _excluded = <String>{};
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _body.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    if (_busy) return false;
    return switch (_action) {
      MassAction.status => _status != null,
      _ => _body.text.trim().isNotEmpty,
    };
  }

  MassUpdateInput _input({required bool dryRun, List<String>? only}) =>
      MassUpdateInput(
        action: _action,
        body: _action == MassAction.status ? null : _body.text,
        status: _status,
        dryRun: dryRun,
        childIds: only,
      );

  Future<void> _run({required bool dryRun}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final only = dryRun
          ? null
          : [
              for (final i in _preview!.items)
                if (i.outcome == MassOutcome.wouldApply &&
                    !_excluded.contains(i.ticketId))
                  i.ticketId,
            ];
      final result = await ref
          .read(apiProvider)
          .helpdesk
          .bundleUpdate(
            id: widget.ticketId,
            body: _input(dryRun: dryRun, only: only),
          );
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (dryRun) {
          _preview = result;
          _excluded.clear();
        } else {
          _done = result;
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = errorMessage(e);
        });
      }
    }
  }

  String _actionLabel(MassAction a) {
    final l = context.l10n;
    return switch (a) {
      MassAction.reply => l.bundleActionReply,
      MassAction.note => l.bundleActionNote,
      MassAction.status => l.bundleActionStatus,
      MassAction.$unknown => '',
    };
  }

  Widget _form(BuildContext context) {
    final l = context.l10n;
    final canReply =
        ref.watch(meProvider).value?.permissions.contains('helpdesk.reply') ??
        false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l.bundleUpdateHelp),
        const SizedBox(height: 12),
        SegmentedButton<MassAction>(
          key: const ValueKey('bundle-action'),
          segments: [
            ButtonSegment(
              value: MassAction.reply,
              enabled: canReply,
              icon: const Icon(AppIcons.mail),
              label: Text(_actionLabel(MassAction.reply)),
            ),
            ButtonSegment(
              value: MassAction.note,
              icon: const Icon(AppIcons.noteAlt),
              label: Text(_actionLabel(MassAction.note)),
            ),
            ButtonSegment(
              value: MassAction.status,
              icon: const Icon(AppIcons.sync),
              label: Text(_actionLabel(MassAction.status)),
            ),
          ],
          selected: {_action},
          onSelectionChanged: (s) => setState(() => _chosen = s.first),
        ),
        const SizedBox(height: 12),
        if (_action != MassAction.status)
          TextField(
            key: const ValueKey('bundle-body'),
            controller: _body,
            minLines: 4,
            maxLines: 8,
            decoration: InputDecoration(
              labelText: _action == MassAction.reply
                  ? l.bundleActionReply
                  : l.bundleActionNote,
              alignLabelWithHint: true,
            ),
          ),
        if (_action != MassAction.status) const SizedBox(height: 8),
        DropdownButtonFormField<String?>(
          key: const ValueKey('bundle-status'),
          initialValue: _status,
          decoration: InputDecoration(
            labelText: _action == MassAction.status
                ? l.status
                : l.bundleStatusAfter,
          ),
          items: [
            if (_action != MassAction.status)
              DropdownMenuItem<String?>(
                value: null,
                child: Text(l.bundleStatusUnchanged),
              ),
            for (final s in _bundleStatuses)
              DropdownMenuItem<String?>(
                value: s,
                child: Text(l.ticketStatus(s)),
              ),
          ],
          onChanged: (s) => setState(() => _status = s),
        ),
      ],
    );
  }

  Widget _results(BuildContext context, MassUpdateResult r) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final preview = r.dryRun;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final i in r.items)
          ListTile(
            key: ValueKey('result-${i.ticketId}'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: preview && i.outcome == MassOutcome.wouldApply
                ? Checkbox(
                    value: !_excluded.contains(i.ticketId),
                    onChanged: _busy
                        ? null
                        : (v) => setState(() {
                            if (v ?? false) {
                              _excluded.remove(i.ticketId);
                            } else {
                              _excluded.add(i.ticketId);
                            }
                          }),
                  )
                : Icon(
                    switch (i.outcome) {
                      MassOutcome.applied => AppIcons.checkCircle,
                      MassOutcome.failed => AppIcons.error,
                      _ => AppIcons.removeCircle,
                    },
                    color: i.outcome == MassOutcome.failed
                        ? theme.colorScheme.error
                        : null,
                  ),
            title: Text(
              '${i.number} · ${i.subject}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              [
                switch (i.outcome) {
                  MassOutcome.wouldApply => l.bundleOutcomeWouldApply,
                  MassOutcome.applied => l.bundleOutcomeApplied,
                  MassOutcome.skipped => l.bundleOutcomeSkipped,
                  _ => l.bundleOutcomeFailed,
                },
                if (i.recipient != null) l.bundleRecipient(i.recipient!),
                if (i.reason != null) i.reason!,
              ].join(' · '),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final done = _done;
    final preview = _preview;
    final selected = preview == null
        ? 0
        : preview.items
              .where(
                (i) =>
                    i.outcome == MassOutcome.wouldApply &&
                    !_excluded.contains(i.ticketId),
              )
              .length;
    return AlertDialog(
      key: const ValueKey('bundle-update-dialog'),
      title: Text(l.bundleUpdateTitle),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (done != null) ...[
                Text(l.bundleDone(done.updated)),
                const SizedBox(height: 8),
                _results(context, done),
              ] else if (preview != null) ...[
                _results(context, preview),
              ] else
                _form(context),
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
        if (done != null)
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.close),
          )
        else ...[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.cancel),
          ),
          if (preview != null) ...[
            TextButton(
              key: const ValueKey('bundle-edit'),
              onPressed: _busy ? null : () => setState(() => _preview = null),
              child: Text(l.bundleEdit),
            ),
            FilledButton(
              key: const ValueKey('bundle-apply'),
              onPressed: _busy || selected == 0
                  ? null
                  : () => _run(dryRun: false),
              child: Text(l.bundleApply(selected)),
            ),
          ] else
            FilledButton(
              key: const ValueKey('bundle-preview'),
              onPressed: _canSubmit ? () => _run(dryRun: true) : null,
              child: Text(l.bundlePreview),
            ),
        ],
      ],
    );
  }
}
