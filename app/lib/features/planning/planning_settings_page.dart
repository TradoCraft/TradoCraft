import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import 'absences_tab.dart';
import 'board_model.dart';
import 'hours_tab.dart';
import 'skills_tab.dart';

/// The technicians and skills catalogue the settings tabs work with.
final planningPeopleProvider = FutureProvider.autoDispose<Board>((ref) {
  final today = dateOnly(DateTime.now());
  return ref
      .watch(apiProvider)
      .planning
      .getPlanningBoard(from: today, to: today);
});

/// Planning administration: absences (planners), working hours, skills and settings (admins).
class PlanningSettingsPage extends ConsumerWidget {
  const PlanningSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final perms = ref.watch(meProvider).value?.permissions ?? const [];
    final admin = perms.contains('planning.admin');
    final people = ref.watch(planningPeopleProvider);
    final tabs = <(String, Widget Function(Board))>[
      (l.planningAbsences, (b) => AbsencesTab(board: b)),
      if (admin) (l.planningHours, (b) => HoursTab(board: b)),
      if (admin)
        (
          l.planningSkills,
          (b) => SkillsTab(
            board: b,
            onChanged: () => ref.invalidate(planningPeopleProvider),
          ),
        ),
      if (admin) (l.planningGeneral, (_) => const SettingsTab()),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.planningSettingsTitle),
          bottom: TabBar(
            isScrollable: true,
            tabs: [for (final t in tabs) Tab(text: t.$1)],
          ),
        ),
        body: people.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text(errorMessage(e))),
          data: (b) => TabBarView(children: [for (final t in tabs) t.$2(b)]),
        ),
      ),
    );
  }
}

/// Travel time between jobs, default job length and time zone.
class SettingsTab extends ConsumerStatefulWidget {
  const SettingsTab({super.key});

  @override
  ConsumerState<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends ConsumerState<SettingsTab> {
  final _buffer = TextEditingController();
  final _length = TextEditingController();
  final _zone = TextEditingController();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    ref.read(apiProvider).planning.getPlanningSettings().then((s) {
      if (!mounted) return;
      setState(() {
        _buffer.text = '${s.travelBufferMinutes}';
        _length.text = '${s.defaultJobMinutes}';
        _zone.text = s.timezone;
        _loaded = true;
      });
    });
  }

  @override
  void dispose() {
    _buffer.dispose();
    _length.dispose();
    _zone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(apiProvider)
          .planning
          .updatePlanningSettings(
            body: Settings(
              travelBufferMinutes: int.tryParse(_buffer.text) ?? 15,
              defaultJobMinutes: int.tryParse(_length.text) ?? 120,
              timezone: _zone.text.trim(),
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
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          key: const ValueKey('buffer'),
          controller: _buffer,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: l.planningTravelBuffer,
            helperText: l.planningTravelBufferHelp,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('length'),
          controller: _length,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: l.planningDefaultJobMinutes),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _zone,
          decoration: InputDecoration(labelText: l.planningTimezone),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            key: const ValueKey('save-settings'),
            onPressed: _save,
            child: Text(l.save),
          ),
        ),
      ],
    );
  }
}
