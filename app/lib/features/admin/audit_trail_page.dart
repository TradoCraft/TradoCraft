import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/format.dart';
import '../../shared/record_history.dart';

/// The company-wide audit trail (ADR 0059), newest first, for users with `audit.view`: who did
/// what to which record and when, filtered by kind of record, action and period, older events on
/// request.
class AuditTrailPage extends ConsumerStatefulWidget {
  const AuditTrailPage({super.key});

  @override
  ConsumerState<AuditTrailPage> createState() => _AuditTrailPageState();
}

class _AuditTrailPageState extends ConsumerState<AuditTrailPage> {
  final _action = TextEditingController();
  final _events = <AuditEvent>[];
  List<String> _entities = const [];
  String? _entity;
  // The action the list on screen was loaded with. The text box can be edited without being
  // confirmed, and "load older" must keep asking for what the list was filtered by.
  String? _appliedAction;
  DateTime? _from;
  DateTime? _to;
  int? _next;
  bool _loading = true;
  Object? _error;
  // A filter change while a page is on its way: only the newest request may fill the list.
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _loadFacets();
    _load(reset: true);
  }

  @override
  void dispose() {
    _action.dispose();
    super.dispose();
  }

  Future<void> _loadFacets() async {
    try {
      final f = await ref.read(apiProvider).audit.getAuditFacets();
      if (mounted) setState(() => _entities = f.entities);
    } catch (_) {
      // The filter then offers "all" only; the trail itself reports real problems.
    }
  }

  Future<void> _load({required bool reset}) async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _events.clear();
        _next = null;
      }
    });
    if (reset) {
      final typed = _action.text.trim();
      _appliedAction = typed.isEmpty ? null : typed;
    }
    final action = _appliedAction;
    try {
      final page = await ref
          .read(apiProvider)
          .audit
          .listAuditEvents(
            entity: _entity,
            action: action,
            // Whole local days: from the start of the first to the start of the day after the last.
            from: _from?.toUtc(),
            to: _to == null
                ? null
                : DateTime(_to!.year, _to!.month, _to!.day + 1).toUtc(),
            beforeId: reset ? null : _next,
          );
      if (!mounted || seq != _seq) return;
      setState(() {
        _events.addAll(page.items);
        _next = page.nextBeforeId;
        _loading = false;
      });
    } catch (e) {
      if (mounted && seq == _seq) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _pick({required bool from}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (from ? _from : _to) ?? now,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (from) {
        _from = DateTime(picked.year, picked.month, picked.day);
      } else {
        _to = DateTime(picked.year, picked.month, picked.day);
      }
    });
    await _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<String?>(
                  key: const ValueKey('audit-entity'),
                  initialValue: _entity,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: l.auditRecordType),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(l.auditAllRecords),
                    ),
                    for (final e in _entities)
                      DropdownMenuItem<String?>(value: e, child: Text(e)),
                  ],
                  onChanged: (v) {
                    setState(() => _entity = v);
                    _load(reset: true);
                  },
                ),
              ),
              SizedBox(
                width: 180,
                child: TextField(
                  key: const ValueKey('audit-action'),
                  controller: _action,
                  decoration: InputDecoration(labelText: l.auditAction),
                  onSubmitted: (_) => _load(reset: true),
                ),
              ),
              OutlinedButton(
                key: const ValueKey('audit-from'),
                onPressed: () => _pick(from: true),
                child: Text(
                  _from == null
                      ? l.auditFrom
                      : '${l.auditFrom}: ${date(_from)}',
                ),
              ),
              OutlinedButton(
                key: const ValueKey('audit-to'),
                onPressed: () => _pick(from: false),
                child: Text(
                  _to == null ? l.auditTo : '${l.auditTo}: ${date(_to)}',
                ),
              ),
              if (_from != null || _to != null)
                TextButton(
                  key: const ValueKey('audit-clear-dates'),
                  onPressed: () {
                    setState(() {
                      _from = null;
                      _to = null;
                    });
                    _load(reset: true);
                  },
                  child: Text(l.auditClearDates),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _list(context)),
      ],
    );
  }

  Widget _list(BuildContext context) {
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
            TextButton(
              onPressed: () => _load(reset: true),
              child: Text(l.retry),
            ),
          ],
        ),
      );
    }
    if (_events.isEmpty) return Center(child: Text(l.auditNoEvents));
    return ListView(
      key: const ValueKey('audit-list'),
      children: [
        for (final e in _events) ...[
          AuditEventTile(event: e, showRecord: true),
          const Divider(height: 1),
        ],
        if (_next != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Center(
              child: OutlinedButton(
                key: const ValueKey('audit-more'),
                onPressed: _loading ? null : () => _load(reset: false),
                child: Text(l.auditLoadMore),
              ),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              errorMessage(_error!),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}
