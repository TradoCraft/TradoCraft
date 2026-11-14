import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import 'board_model.dart';
import 'planning_adapter.dart';
import '../../shared/app_icons.dart';

final _day = DateFormat('dd/MM/yyyy');

/// Vacation, sick leave and training of the technicians.
class AbsencesTab extends ConsumerStatefulWidget {
  const AbsencesTab({super.key, required this.board});
  final Board board;

  @override
  ConsumerState<AbsencesTab> createState() => _AbsencesTabState();
}

class _AbsencesTabState extends ConsumerState<AbsencesTab> {
  late Future<List<Absence>> _list;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _list = ref
        .read(apiProvider)
        .planning
        .listAbsences(
          from: dateOnly(DateTime.now()).subtract(const Duration(days: 30)),
        );
  }

  Future<void> _add() async {
    final input = await showDialog<AbsenceInput>(
      context: context,
      builder: (_) => _AbsenceDialog(technicians: widget.board.technicians),
    );
    if (input == null || !mounted) return;
    try {
      await ref.read(apiProvider).planning.createAbsence(body: input);
      setState(_load);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(errorMessage(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              key: const ValueKey('add-absence'),
              icon: const Icon(AppIcons.add),
              label: Text(l.planningAddAbsence),
              onPressed: _add,
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Absence>>(
            future: _list,
            builder: (context, s) {
              if (s.hasError) {
                return Center(child: Text(errorMessage(s.error!)));
              }
              if (!s.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (s.data!.isEmpty) {
                return Center(child: Text(l.planningNoAbsences));
              }
              return ListView(
                children: [
                  for (final a in s.data!)
                    ListTile(
                      title: Text(
                        '${a.userName} · ${l.planningAbsenceKind(a.kind)}',
                      ),
                      subtitle: Text(
                        '${_day.format(a.fromDate)} – ${_day.format(a.toDate)}${a.note.isEmpty ? '' : '\n${a.note}'}',
                      ),
                      trailing: IconButton(
                        tooltip: l.remove,
                        icon: const Icon(AppIcons.delete),
                        onPressed: () async {
                          await ref
                              .read(apiProvider)
                              .planning
                              .deleteAbsence(id: a.id);
                          if (mounted) setState(_load);
                        },
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AbsenceDialog extends StatefulWidget {
  const _AbsenceDialog({required this.technicians});
  final List<BoardTechnician> technicians;

  @override
  State<_AbsenceDialog> createState() => _AbsenceDialogState();
}

class _AbsenceDialogState extends State<_AbsenceDialog> {
  String? _user;
  String _kind = 'vacation';
  DateTime _from = dateOnly(DateTime.now());
  DateTime _to = dateOnly(DateTime.now());
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pick(bool from) async {
    final d = await showDatePicker(
      context: context,
      initialDate: from ? _from : _to,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
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

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.planningAddAbsence),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              key: const ValueKey('absence-user'),
              initialValue: _user,
              decoration: InputDecoration(labelText: l.planningTechnician),
              items: [
                for (final t in widget.technicians)
                  DropdownMenuItem(value: t.userId, child: Text(t.displayName)),
              ],
              onChanged: (v) => setState(() => _user = v),
            ),
            DropdownButtonFormField<String>(
              initialValue: _kind,
              decoration: InputDecoration(labelText: l.planningKind),
              items: [
                for (final k in ['vacation', 'sick', 'training', 'other'])
                  DropdownMenuItem(
                    value: k,
                    child: Text(l.planningAbsenceKind(k)),
                  ),
              ],
              onChanged: (v) => setState(() => _kind = v!),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pick(true),
                    child: Text('${l.from}: ${_day.format(_from)}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pick(false),
                    child: Text('${l.to}: ${_day.format(_to)}'),
                  ),
                ),
              ],
            ),
            TextField(
              controller: _note,
              decoration: InputDecoration(labelText: l.notes),
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
          key: const ValueKey('save-absence'),
          onPressed: _user == null
              ? null
              : () => Navigator.pop(
                  context,
                  AbsenceInput(
                    userId: _user!,
                    fromDate: _from,
                    toDate: _to,
                    kind: _kind,
                    note: _note.text.trim(),
                  ),
                ),
          child: Text(l.save),
        ),
      ],
    );
  }
}
