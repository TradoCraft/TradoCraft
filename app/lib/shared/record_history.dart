import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../app/api.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';

final _when = DateFormat('dd/MM/yyyy HH:mm');

/// Who did it: the user's name, else their e-mail address, else "System" (a customer in the
/// portal, a background job: the event has no staff user).
String auditWho(AppLocalizations l, AuditEvent e) {
  final name = e.userName?.trim();
  if (name != null && name.isNotEmpty) return name;
  final email = e.userEmail?.trim();
  if (email != null && email.isNotEmpty) return email;
  return l.auditSystem;
}

/// One value of an audit event, as short text.
String auditValue(Object? v) {
  if (v == null) return '–';
  if (v is String) return v.isEmpty ? '""' : v;
  if (v is num || v is bool) return '$v';
  return jsonEncode(v);
}

/// One audited event: what happened, who did it and when, and what the module recorded of it
/// (ADR 0059), most usefully the fields that changed with their old and new value.
class AuditEventTile extends StatelessWidget {
  const AuditEventTile({
    super.key,
    required this.event,
    this.showRecord = false,
  });

  final AuditEvent event;

  /// Also name the kind of record, for the company-wide trail where records are mixed.
  final bool showRecord;

  /// The lines under the heading: one per changed field, else the other recorded values.
  List<String> _details(AppLocalizations l) {
    final data = event.data;
    if (data is! Map || data.isEmpty) return [l.auditNoDetails];
    final lines = <String>[];
    final changes = data['changes'];
    if (changes is Map) {
      changes.forEach((field, c) {
        if (c is Map) {
          lines.add(
            '$field: ${auditValue(c['from'])} → ${auditValue(c['to'])}',
          );
        }
      });
    }
    final rest = [
      for (final e in data.entries)
        if (e.key != 'changes') '${e.key}: ${auditValue(e.value)}',
    ];
    // In full: a value cut short could not be read, or copied, anywhere.
    if (rest.isNotEmpty) lines.add(rest.join(', '));
    return lines.isEmpty ? [l.auditNoDetails] : lines;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(event.action, style: theme.textTheme.titleSmall),
              if (showRecord) Text('·  ${event.entity}', style: muted),
              // Which record: the id, selectable, to look the record up or filter by it.
              if (showRecord) SelectableText(event.entityId, style: muted),
            ],
          ),
          Text(
            '${auditWho(l, event)}  ·  ${_when.format(event.occurredAt.toLocal())}',
            style: muted,
          ),
          for (final line in _details(l))
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: SelectableText(line, style: theme.textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}

/// The history of one record (ADR 0059) in a dialog, newest first, older events on request.
Future<void> showRecordHistory(
  BuildContext context, {
  required String entity,
  required String id,
  required String title,
}) => showDialog<void>(
  context: context,
  builder: (_) => _HistoryDialog(entity: entity, id: id, title: title),
);

/// A "History" button for a record's screen. Nothing for users without `audit.view`.
class RecordHistoryButton extends ConsumerWidget {
  const RecordHistoryButton({
    super.key,
    required this.entity,
    required this.id,
    required this.title,
  });

  final String entity;
  final String id;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!can(ref, 'audit.view')) return const SizedBox.shrink();
    return TextButton.icon(
      key: const ValueKey('record-history'),
      icon: const Icon(AppIcons.history),
      label: Text(context.l10n.auditHistory),
      onPressed: () =>
          showRecordHistory(context, entity: entity, id: id, title: title),
    );
  }
}

class _HistoryDialog extends ConsumerStatefulWidget {
  const _HistoryDialog({
    required this.entity,
    required this.id,
    required this.title,
  });

  final String entity;
  final String id;
  final String title;

  @override
  ConsumerState<_HistoryDialog> createState() => _HistoryDialogState();
}

class _HistoryDialogState extends ConsumerState<_HistoryDialog> {
  final _events = <AuditEvent>[];
  int? _next;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref
          .read(apiProvider)
          .audit
          .getRecordHistory(
            entity: widget.entity,
            id: widget.id,
            beforeId: _next,
          );
      if (!mounted) return;
      setState(() {
        _events.addAll(page.items);
        _next = page.nextBeforeId;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.auditHistoryTitle(widget.title)),
      content: SizedBox(width: 560, height: 440, child: _body(context)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.close),
        ),
      ],
    );
  }

  Widget _body(BuildContext context) {
    final l = context.l10n;
    if (_events.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_events.isEmpty && _error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(errorMessage(_error!)),
            TextButton(onPressed: _load, child: Text(l.retry)),
          ],
        ),
      );
    }
    if (_events.isEmpty) return Center(child: Text(l.auditNoEvents));
    return ListView(
      children: [
        for (final e in _events) ...[
          AuditEventTile(event: e),
          const Divider(height: 1),
        ],
        if (_next != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextButton(
              key: const ValueKey('history-more'),
              onPressed: _loading ? null : _load,
              child: Text(l.auditLoadMore),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              errorMessage(_error!),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}
