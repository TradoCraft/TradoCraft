/// The chatter of a record (ADR 0086): followers, scheduled activities, a note composer and the
/// feed of notes and change messages. Self-contained: it needs a record kind and an id.
library;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/api.dart';
import '../../../core/theme/tokens.dart';
import '../../../l10n/l10n.dart';
import '../../../shared/app_icons.dart';
import '../../../shared/attachments.dart';
import '../../../features/helpdesk/ticket_screen.dart' show usersProvider;
import 'chatter_repository.dart';

final _when = DateFormat('dd/MM/yyyy HH:mm');
final _day = DateFormat('dd/MM/yyyy');

class ChatterPanel extends ConsumerStatefulWidget {
  const ChatterPanel({
    super.key,
    required this.kind,
    required this.recordId,
    this.refresh,
    this.pickFiles,
  });

  final ChatterKind kind;
  final String recordId;

  /// Reloads everything when it notifies (a colleague posted, see
  /// `RecordFormController.chatterTick`).
  final Listenable? refresh;

  /// Chooses the files to attach; the platform dialog by default, replaced in tests.
  final AttachmentPicker? pickFiles;

  @override
  ConsumerState<ChatterPanel> createState() => _ChatterPanelState();
}

class _ChatterPanelState extends ConsumerState<ChatterPanel> {
  final _composer = TextEditingController();
  List<ThreadItem> _items = const [];
  String? _next;
  List<Activity> _activities = const [];
  Followers? _followers;
  bool _loading = true;
  bool _failed = false;
  bool _posting = false;
  List<FileInfo> _pending = const [];
  String? _error;
  int _generation = 0;

  ChatterRepository get _repo => ref.read(chatterRepositoryProvider);

  @override
  void initState() {
    super.initState();
    widget.refresh?.addListener(_reload);
    _reload();
  }

  @override
  void didUpdateWidget(ChatterPanel old) {
    super.didUpdateWidget(old);
    if (old.refresh != widget.refresh) {
      old.refresh?.removeListener(_reload);
      widget.refresh?.addListener(_reload);
    }
    if (old.recordId != widget.recordId || old.kind != widget.kind) _reload();
  }

  @override
  void dispose() {
    widget.refresh?.removeListener(_reload);
    _composer.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final gen = ++_generation;
    try {
      final results = await Future.wait<Object>([
        _repo.thread(widget.kind, widget.recordId),
        _repo.activities(widget.kind, widget.recordId),
        _repo.followers(widget.kind, widget.recordId),
      ]);
      if (!mounted || gen != _generation) return;
      final page = results[0] as ThreadPage;
      setState(() {
        _items = page.items;
        _next = page.nextBeforeId;
        _activities = results[1] as List<Activity>;
        _followers = results[2] as Followers;
        _loading = false;
        _failed = false;
      });
      // Opening the record counts as reading its thread.
      _repo
          .markRead(widget.kind, widget.recordId)
          .then((_) {
            // The bell's unread list and due activities changed.
            if (mounted) ref.invalidate(chatterInboxProvider);
          })
          .catchError((_) {});
    } catch (_) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _older() async {
    final next = _next;
    if (next == null) return;
    try {
      final page = await _repo.thread(
        widget.kind,
        widget.recordId,
        beforeId: next,
      );
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...page.items];
        _next = page.nextBeforeId;
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  Future<void> _post() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _posting) return;
    setState(() {
      _posting = true;
      _error = null;
    });
    try {
      await _repo.post(
        widget.kind,
        widget.recordId,
        text,
        fileIds: [for (final f in _pending) f.id],
      );
      _composer.clear();
      _pending = const [];
      await _reload();
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      await _reload();
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  Future<void> _toggleFollow() async {
    final f = _followers;
    if (f == null) return;
    await _run(() async {
      final next = f.following
          ? await _repo.unfollow(widget.kind, widget.recordId)
          : await _repo.follow(widget.kind, widget.recordId);
      if (mounted) setState(() => _followers = next);
    });
  }

  Future<void> _editNote(ThreadItem item) async {
    final text = await _askText(
      context,
      title: context.l10n.chatterEditNote,
      initial: item.body,
      confirm: context.l10n.chatterSaveNote,
    );
    if (text == null || text.trim().isEmpty) return;
    await _run(() => _repo.edit(item.id, text.trim()));
  }

  Future<void> _complete(Activity a) async {
    final note = await _askText(
      context,
      title: context.l10n.chatterMarkDone,
      hint: context.l10n.chatterDoneNote,
      confirm: context.l10n.chatterMarkDone,
      allowEmpty: true,
    );
    if (note == null) return;
    await _run(() => _repo.complete(a.id, note.trim()));
  }

  Future<void> _editActivity(Activity a) async {
    final input = await showDialog<ActivityInput>(
      context: context,
      builder: (_) => _ScheduleDialog(initial: a),
    );
    if (input == null) return;
    await _run(
      () => _repo
          .updateActivity(
            a.id,
            ActivityPatch(
              kind: input.kind,
              summary: input.summary,
              note: input.note ?? '',
              assigneeId: input.assigneeId,
              dueDate: input.dueDate,
            ),
          )
          .then((_) {}),
    );
  }

  Future<void> _schedule() async {
    final input = await showDialog<ActivityInput>(
      context: context,
      builder: (_) => const _ScheduleDialog(),
    );
    if (input == null) return;
    await _run(
      () => _repo.schedule(widget.kind, widget.recordId, input).then((_) {}),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final canWrite = can(ref, widget.kind.write);
    return Container(
      key: const ValueKey('chatter-panel'),
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: Radii.large,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(l.chatterTitle, style: theme.textTheme.titleMedium),
              const Spacer(),
              if (_followers != null) ...[
                Text(
                  l.chatterFollowers(_followers!.items.length),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(width: Space.sm),
                _followers!.following
                    ? FilledButton.tonalIcon(
                        key: const ValueKey('chatter-follow'),
                        onPressed: _toggleFollow,
                        icon: const Icon(AppIcons.check, size: 18),
                        label: Text(l.chatterFollowing),
                      )
                    : OutlinedButton(
                        key: const ValueKey('chatter-follow'),
                        onPressed: _toggleFollow,
                        child: Text(l.chatterFollow),
                      ),
              ],
            ],
          ),
          const SizedBox(height: Space.md),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_failed)
            Row(
              children: [
                Expanded(child: Text(l.chatterLoadFailed)),
                TextButton(onPressed: _reload, child: Text(l.chatterRetry)),
              ],
            )
          else ...[
            _activitiesSection(context, canWrite),
            if (canWrite) _composerSection(context),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.sm),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            if (_items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.md),
                child: Text(
                  l.chatterEmpty,
                  key: const ValueKey('chatter-empty'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            for (final item in _items) _entry(context, item),
            if (_next != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const ValueKey('chatter-older'),
                  onPressed: _older,
                  child: Text(l.chatterLoadOlder),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _composerSection(BuildContext context) {
    final l = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, control: true): _post,
          const SingleActivator(LogicalKeyboardKey.enter, meta: true): _post,
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('chatter-composer'),
              controller: _composer,
              minLines: 2,
              maxLines: 6,
              maxLength: 10000,
              buildCounter: (
                _, {
                required currentLength,
                required isFocused,
                maxLength,
              }) => null,
              decoration: InputDecoration(
                hintText: l.chatterNoteHint,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: Space.sm),
            AttachmentComposer(
              dio: ref.read(dioProvider),
              uploadPath: widget.kind.filesPath(widget.recordId),
              files: _pending,
              pick: widget.pickFiles ?? pickAttachmentFiles,
              onChanged: (files) => setState(() => _pending = files),
            ),
            const SizedBox(height: Space.sm),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                key: const ValueKey('chatter-post'),
                onPressed: _posting ? null : _post,
                child: Text(l.chatterPost),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _activitiesSection(BuildContext context, bool canWrite) {
    final l = context.l10n;
    final theme = Theme.of(context);
    if (_activities.isEmpty && !canWrite) return const SizedBox.shrink();
    final me = ref.watch(meProvider).value?.userId;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(l.chatterActivities, style: theme.textTheme.titleSmall),
              const Spacer(),
              if (canWrite)
                TextButton.icon(
                  key: const ValueKey('chatter-schedule'),
                  onPressed: _schedule,
                  icon: const Icon(AppIcons.add, size: 18),
                  label: Text(l.chatterSchedule),
                ),
            ],
          ),
          for (final a in _activities)
            ListTile(
              key: ValueKey('activity-${a.id}'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(_kindIcon(a.kind)),
              title: Text('${chatterKindLabel(l, a.kind)}: ${a.summary}'),
              subtitle: Text(
                '${a.assigneeName} · ${a.overdue ? '${l.chatterOverdue} · ' : ''}'
                '${l.chatterDueOn(_day.format(a.dueDate))}',
                style: a.overdue
                    ? TextStyle(color: theme.colorScheme.error)
                    : null,
              ),
              trailing: canWrite
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (a.assigneeId == me || a.createdBy == me)
                          IconButton(
                            key: ValueKey('activity-edit-${a.id}'),
                            tooltip: l.chatterEditNote,
                            icon: const Icon(AppIcons.edit),
                            onPressed: () => _editActivity(a),
                          ),
                        IconButton(
                          key: ValueKey('activity-done-${a.id}'),
                          tooltip: l.chatterMarkDone,
                          icon: const Icon(AppIcons.check),
                          onPressed: () => _complete(a),
                        ),
                        if (a.assigneeId == me || a.createdBy == me)
                          IconButton(
                            tooltip: l.chatterDeleteNote,
                            icon: const Icon(AppIcons.delete),
                            onPressed: () =>
                                _run(() => _repo.deleteActivity(a.id)),
                          ),
                      ],
                    )
                  : null,
            ),
        ],
      ),
    );
  }

  Widget _entry(BuildContext context, ThreadItem item) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final author = item.authorName ?? l.chatterSystemActor;
    final when = _when.format(item.createdAt.toLocal());
    final system = item.kind == 'system';
    final lines = system ? _changeLines(l, item, author) : const <String>[];
    return Padding(
      key: ValueKey('chatter-${item.id}'),
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                system ? AppIcons.history : AppIcons.chat,
                size: 16,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(width: Space.sm),
              Flexible(
                child: Text(
                  system ? when : '$author · $when',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (item.editedAt != null)
                Padding(
                  padding: const EdgeInsets.only(left: Space.sm),
                  child: Text(
                    '(${l.chatterEdited})',
                    style: theme.textTheme.labelSmall,
                  ),
                ),
              if (item.editable) ...[
                const Spacer(),
                IconButton(
                  key: ValueKey('chatter-edit-${item.id}'),
                  tooltip: l.chatterEditNote,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(AppIcons.edit, size: 18),
                  onPressed: () => _editNote(item),
                ),
                IconButton(
                  key: ValueKey('chatter-delete-${item.id}'),
                  tooltip: l.chatterDeleteNote,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(AppIcons.delete, size: 18),
                  onPressed: () => _run(() => _repo.delete(item.id)),
                ),
              ],
            ],
          ),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 2),
              child: Text(line, style: theme.textTheme.bodySmall),
            ),
          if (item.body.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 2),
              child: SelectableText(item.body),
            ),
          if (item.files.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 24),
              child: AttachmentChips(
                files: item.files,
                dio: ref.read(dioProvider),
                pathFor: (id) =>
                    '${widget.kind.filesPath(widget.recordId)}/$id',
              ),
            ),
        ],
      ),
    );
  }
}

IconData _kindIcon(String kind) => switch (kind) {
  'call' => AppIcons.call,
  'email' => AppIcons.mail,
  'meeting' => AppIcons.event,
  _ => AppIcons.checklist,
};

String chatterKindLabel(AppLocalizations l, String kind) => switch (kind) {
  'call' => l.chatterKindCall,
  'email' => l.chatterKindEmail,
  'meeting' => l.chatterKindMeeting,
  _ => l.chatterKindTodo,
};

String _fieldLabel(AppLocalizations l, String field) => switch (field) {
  'name' => l.chatterFieldName,
  'vat_number' => l.chatterFieldVatNumber,
  'vat_regime' => l.chatterFieldVatRegime,
  'email' => l.chatterFieldEmail,
  'phone' => l.chatterFieldPhone,
  'language' => l.chatterFieldLanguage,
  'active' => l.chatterFieldActive,
  'discount_percent' => l.chatterFieldDiscount,
  'status' => l.chatterFieldStatus,
  'stage' => l.chatterFieldStage,
  'revision' => l.chatterFieldRevision,
  'order_sent' => l.chatterFieldOrderSent,
  'order_confirmed' => l.chatterFieldOrderConfirmed,
  _ => field,
};

String _value(Object? v) => switch (v) {
  null => '—',
  true => '✓',
  false => '✗',
  _ => '$v',
};

/// One readable line per tracked field of a change message.
List<String> _changeLines(AppLocalizations l, ThreadItem item, String who) {
  final changes = item.changes;
  if (changes is! List) return const [];
  final lines = <String>[];
  for (final c in changes) {
    if (c is! Map) continue;
    final field = '${c['field']}';
    if (field == 'activity_done') {
      lines.add(
        l.chatterActivityDone(
          who,
          chatterKindLabel(l, '${c['from']}'),
          '${c['to']}',
        ),
      );
    } else {
      lines.add(
        l.chatterChanged(
          who,
          _fieldLabel(l, field),
          _value(c['from']),
          _value(c['to']),
        ),
      );
    }
  }
  return lines;
}

/// A small dialog with one text field; null when cancelled.
Future<String?> _askText(
  BuildContext context, {
  required String title,
  required String confirm,
  String initial = '',
  String? hint,
  bool allowEmpty = false,
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 420,
        child: TextField(
          key: const ValueKey('chatter-dialog-text'),
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 6,
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
        ),
        FilledButton(
          key: const ValueKey('chatter-dialog-ok'),
          onPressed: () {
            final t = controller.text;
            if (!allowEmpty && t.trim().isEmpty) return;
            Navigator.pop(ctx, t);
          },
          child: Text(confirm),
        ),
      ],
    ),
  );
}

/// Schedules an activity: kind, summary, due date and assignee (default: the caller).
class _ScheduleDialog extends ConsumerStatefulWidget {
  const _ScheduleDialog({this.initial});

  /// The activity being edited; null to schedule a new one.
  final Activity? initial;

  @override
  ConsumerState<_ScheduleDialog> createState() => _ScheduleDialogState();
}

class _ScheduleDialogState extends ConsumerState<_ScheduleDialog> {
  late final _summary = TextEditingController(text: widget.initial?.summary);
  late final _note = TextEditingController(text: widget.initial?.note);
  late ActivityKind _kind = ActivityKind.fromJson(
    widget.initial?.kind ?? 'todo',
  );
  late DateTime _due = widget.initial != null
      ? DateUtils.dateOnly(widget.initial!.dueDate)
      : DateUtils.dateOnly(DateTime.now().add(const Duration(days: 1)));
  late String? _assignee = widget.initial?.assigneeId;

  @override
  void dispose() {
    _summary.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final users = ref.watch(usersProvider).value ?? const <CompanyUser>[];
    final me = ref.watch(meProvider).value?.userId;
    final assignee = _assignee ?? me;
    return AlertDialog(
      title: Text(
        widget.initial == null ? l.chatterSchedule : l.chatterEditNote,
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<ActivityKind>(
              key: const ValueKey('activity-kind'),
              initialValue: _kind,
              items: [
                for (final k in const [
                  ActivityKind.todo,
                  ActivityKind.call,
                  ActivityKind.email,
                  ActivityKind.meeting,
                ])
                  DropdownMenuItem(
                    value: k,
                    child: Text(chatterKindLabel(l, k.json ?? 'todo')),
                  ),
              ],
              onChanged: (k) => setState(() => _kind = k ?? _kind),
            ),
            const SizedBox(height: Space.md),
            TextField(
              key: const ValueKey('activity-summary'),
              controller: _summary,
              autofocus: true,
              maxLength: 200,
              decoration: InputDecoration(labelText: l.chatterSummary),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: Space.sm),
            if (users.isNotEmpty)
              DropdownButtonFormField<String>(
                key: const ValueKey('activity-assignee'),
                initialValue: users.any((u) => u.id == assignee)
                    ? assignee
                    : null,
                decoration: InputDecoration(labelText: l.chatterAssignee),
                items: [
                  for (final u in users)
                    DropdownMenuItem(value: u.id, child: Text(u.displayName)),
                ],
                onChanged: (v) => setState(() => _assignee = v),
              ),
            const SizedBox(height: Space.sm),
            OutlinedButton.icon(
              key: const ValueKey('activity-due'),
              icon: const Icon(AppIcons.event, size: 18),
              label: Text('${l.chatterDueDate}: ${_day.format(_due)}'),
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _due,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (picked != null) setState(() => _due = picked);
              },
            ),
            const SizedBox(height: Space.sm),
            TextField(
              key: const ValueKey('activity-note'),
              controller: _note,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(labelText: l.chatterNote),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          key: const ValueKey('activity-ok'),
          onPressed: _summary.text.trim().isEmpty || assignee == null
              ? null
              : () => Navigator.pop(
                  context,
                  ActivityInput(
                    kind: _kind,
                    summary: _summary.text.trim(),
                    note: _note.text.trim(),
                    assigneeId: assignee,
                    dueDate: _due,
                  ),
                ),
          child: Text(
            widget.initial == null ? l.chatterSchedule : l.chatterSaveNote,
          ),
        ),
      ],
    );
  }
}
