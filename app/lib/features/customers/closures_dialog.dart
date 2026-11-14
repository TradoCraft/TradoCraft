import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/actions.dart';
import '../../shared/app_icons.dart';
import '../../shared/format.dart';
import '../planning/board_model.dart';

/// The periods in which a customer is closed and cannot receive parcels or shipments.
/// Staff with `closures.write` (a secretary) add, change and remove them; everyone else only sees
/// them. Shipment planning checks them through `GET /customers/{id}/closures/check`.
class ClosuresDialog extends ConsumerStatefulWidget {
  const ClosuresDialog({super.key, required this.customer});
  final Customer customer;

  @override
  ConsumerState<ClosuresDialog> createState() => _ClosuresDialogState();
}

class _ClosuresDialogState extends ConsumerState<ClosuresDialog> {
  List<Closure>? _closures;
  bool _showPast = false;
  String? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Loads the list. Only the latest request may update the screen, so a slow answer to an
  /// earlier one (e.g. before the "show past" switch was flipped) cannot overwrite a newer one.
  Future<void> _load() async {
    final request = ++_request;
    try {
      // Without `from` the API shows what has not ended yet; an early date shows everything.
      final list = await ref
          .read(apiProvider)
          .crm
          .listCustomerClosures(
            id: widget.customer.id,
            from: _showPast ? DateTime(1900) : null,
          );
      if (mounted && request == _request) {
        setState(() {
          _closures = list;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && request == _request) {
        setState(() => _error = errorMessage(e));
      }
    }
  }

  Future<void> _remove(Closure c) async {
    final l = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l.remove),
        content: Text(
          [
            '${_period(c)} · ${l.closureKind(c.kind)}',
            if (c.notes.isNotEmpty) c.notes,
          ].join('\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.remove),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await runAction(
      context,
      () => ref
          .read(apiProvider)
          .crm
          .deleteClosure(id: widget.customer.id, closureId: c.id),
    );
    _load();
  }

  String _period(Closure c) => dateOnly(c.startsOn) == dateOnly(c.endsOn)
      ? date(c.startsOn)
      : '${date(c.startsOn)} – ${date(c.endsOn)}';

  Future<void> _edit([Closure? existing]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) =>
          ClosureForm(customer: widget.customer, existing: existing),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final canWrite =
        ref.watch(meProvider).value?.permissions.contains('closures.write') ??
        false;
    final list = _closures;
    return AlertDialog(
      title: Text('${l.closures} · ${widget.customer.name}'),
      content: SizedBox(
        width: 560,
        child: _error != null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  TextButton.icon(
                    icon: const Icon(AppIcons.refresh),
                    label: Text(l.retry),
                    onPressed: _load,
                  ),
                ],
              )
            : list == null
            ? const LinearProgressIndicator()
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (list.isEmpty) Text(l.noClosures),
                    for (final c in list)
                      ListTile(
                        leading: const Icon(AppIcons.eventBusy),
                        title: Text('${_period(c)} · ${l.closureKind(c.kind)}'),
                        subtitle: c.notes.isEmpty ? null : Text(c.notes),
                        trailing: canWrite
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: l.edit,
                                    icon: const Icon(AppIcons.edit),
                                    onPressed: () => _edit(c),
                                  ),
                                  IconButton(
                                    tooltip: l.remove,
                                    icon: const Icon(AppIcons.delete),
                                    onPressed: () => _remove(c),
                                  ),
                                ],
                              )
                            : null,
                      ),
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(l.closuresShowPast),
                      value: _showPast,
                      onChanged: (v) {
                        setState(() => _showPast = v);
                        _load();
                      },
                    ),
                  ],
                ),
              ),
      ),
      actions: [
        if (canWrite)
          TextButton.icon(
            icon: const Icon(AppIcons.add),
            label: Text(l.addClosure),
            onPressed: _edit,
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.close),
        ),
      ],
    );
  }
}

/// Adds a closure, or changes [existing]. Pops `true` once saved.
class ClosureForm extends ConsumerStatefulWidget {
  const ClosureForm({super.key, required this.customer, this.existing});
  final Customer customer;
  final Closure? existing;

  @override
  ConsumerState<ClosureForm> createState() => _ClosureFormState();
}

class _ClosureFormState extends ConsumerState<ClosureForm> {
  late String _kind = widget.existing?.kind ?? 'holiday';
  late DateTime _from = dateOnly(widget.existing?.startsOn ?? DateTime.now());
  late DateTime _to = dateOnly(widget.existing?.endsOn ?? _from);
  late final _notes = TextEditingController(text: widget.existing?.notes);
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pick(bool from) async {
    final d = await showDatePicker(
      context: context,
      initialDate: from ? _from : _to,
      // A stored closure may lie outside the usual range; the picker asserts on a date outside it.
      firstDate: _from.isBefore(DateTime(2000)) ? _from : DateTime(2000),
      lastDate: _to.isAfter(DateTime(2100)) ? _to : DateTime(2100),
    );
    if (d == null) return;
    setState(() {
      if (from) {
        _from = dateOnly(d);
        if (_to.isBefore(_from)) _to = _from;
      } else {
        _to = dateOnly(d);
        if (_to.isBefore(_from)) _from = _to;
      }
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final body = ClosureInput(
      startsOn: _from,
      endsOn: _to,
      kind: _kind,
      notes: _notes.text.trim(),
    );
    final crm = ref.read(apiProvider).crm;
    try {
      final e = widget.existing;
      if (e == null) {
        await crm.createClosure(id: widget.customer.id, body: body);
      } else {
        await crm.updateClosure(
          id: widget.customer.id,
          closureId: e.id,
          body: body,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorMessage(e);
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    const gap = SizedBox(height: 12);
    return AlertDialog(
      title: Text(widget.existing == null ? l.addClosure : l.editClosure),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _kind,
              decoration: InputDecoration(labelText: l.closureKindLabel),
              items: [
                for (final k in closureKinds)
                  DropdownMenuItem(value: k, child: Text(l.closureKind(k))),
              ],
              onChanged: (v) => setState(() => _kind = v!),
            ),
            gap,
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pick(true),
                    child: Text('${l.from} ${date(_from)}'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pick(false),
                    child: Text('${l.until} ${date(_to)}'),
                  ),
                ),
              ],
            ),
            gap,
            TextField(
              controller: _notes,
              decoration: InputDecoration(labelText: l.notes),
            ),
            if (_error != null) ...[
              gap,
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(onPressed: _saving ? null : _save, child: Text(l.save)),
      ],
    );
  }
}
