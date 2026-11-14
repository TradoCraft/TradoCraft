import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import 'planning_adapter.dart';
import '../../shared/app_icons.dart';

/// Working hours of the company (the default) and of each technician; several blocks per day.
/// A technician without blocks of their own follows the company default.
class HoursTab extends ConsumerStatefulWidget {
  const HoursTab({super.key, required this.board});
  final Board board;

  @override
  ConsumerState<HoursTab> createState() => _HoursTabState();
}

class _HoursTabState extends ConsumerState<HoursTab> {
  /// null = the company default.
  String? _user;
  bool _loaded = false;
  final Map<int, List<(int, int)>> _blocks = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(apiProvider).planning;
    final rows = _user == null
        ? await api.listWorkingHours(defaults: true)
        : await api.listWorkingHours(userId: _user);
    if (!mounted) return;
    setState(() {
      _blocks.clear();
      for (final r in rows) {
        (_blocks[r.weekday] ??= []).add((
          minutesOfText(r.startTime),
          minutesOfText(r.endTime),
        ));
      }
      _loaded = true;
    });
  }

  Future<void> _pickTime(int weekday, int index, bool start) async {
    final cur = _blocks[weekday]![index];
    final m = start ? cur.$1 : cur.$2;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60),
    );
    if (t == null) return;
    final v = t.hour * 60 + t.minute;
    setState(
      () => _blocks[weekday]![index] = start ? (v, cur.$2) : (cur.$1, v),
    );
  }

  Future<void> _save() async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(apiProvider)
          .planning
          .setWorkingHours(
            body: WorkingHoursInput(
              userId: _user,
              slots: [
                for (final e in _blocks.entries)
                  for (final b in e.value)
                    HoursSlotInput(
                      weekday: e.key,
                      startTime: clockText(b.$1),
                      endTime: clockText(b.$2),
                    ),
              ],
            ),
          );
      messenger.showSnackBar(SnackBar(content: Text(l.saved)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(errorMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final locale = Localizations.localeOf(context).toString();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButton<String?>(
          key: const ValueKey('hours-scope'),
          value: _user,
          items: [
            DropdownMenuItem(value: null, child: Text(l.planningDefaultHours)),
            for (final t in widget.board.technicians)
              DropdownMenuItem(value: t.userId, child: Text(t.displayName)),
          ],
          onChanged: (v) {
            _user = v;
            _loaded = false;
            _load();
          },
        ),
        if (_user != null && _loaded && _blocks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(l.planningUsesDefault),
          ),
        if (!_loaded) const Center(child: CircularProgressIndicator()),
        if (_loaded)
          for (var wd = 1; wd <= 7; wd++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 110,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      // 2026-11-02 is a Monday.
                      child: Text(
                        DateFormat(
                          'EEEE',
                          locale,
                        ).format(DateTime(2026, 11, 1 + wd)),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (var i = 0; i < (_blocks[wd]?.length ?? 0); i++)
                          InputChip(
                            key: ValueKey('block-$wd-$i'),
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                InkWell(
                                  onTap: () => _pickTime(wd, i, true),
                                  child: Text(clockText(_blocks[wd]![i].$1)),
                                ),
                                const Text(' – '),
                                InkWell(
                                  onTap: () => _pickTime(wd, i, false),
                                  child: Text(clockText(_blocks[wd]![i].$2)),
                                ),
                              ],
                            ),
                            onDeleted: () =>
                                setState(() => _blocks[wd]!.removeAt(i)),
                          ),
                        ActionChip(
                          key: ValueKey('add-block-$wd'),
                          avatar: const Icon(AppIcons.add, size: 16),
                          label: Text(l.planningAddBlock),
                          onPressed: () => setState(() {
                            final list = _blocks[wd] ??= [];
                            list.add(
                              list.isEmpty
                                  ? (8 * 60, 12 * 60)
                                  : (13 * 60, 17 * 60),
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            key: const ValueKey('save-hours'),
            onPressed: _loaded ? _save : null,
            child: Text(l.save),
          ),
        ),
      ],
    );
  }
}
