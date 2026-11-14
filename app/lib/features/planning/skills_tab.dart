import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/app_icons.dart';

/// The skills catalogue and the skills of each technician (level 1 to 3).
class SkillsTab extends ConsumerStatefulWidget {
  const SkillsTab({super.key, required this.board, required this.onChanged});
  final Board board;
  final VoidCallback onChanged;

  @override
  ConsumerState<SkillsTab> createState() => _SkillsTabState();
}

class _SkillsTabState extends ConsumerState<SkillsTab> {
  late List<Skill> _skills = widget.board.skills;
  late final Map<String, Map<String, int>> _levels = {
    for (final t in widget.board.technicians)
      t.userId: {for (final s in t.skills) s.skillId: s.level},
  };

  PlanningClient get _api => ref.read(apiProvider).planning;

  Future<void> _reloadSkills() async {
    final s = await _api.listSkills();
    if (!mounted) return;
    setState(() => _skills = s);
    widget.onChanged();
  }

  Future<void> _edit([Skill? skill]) async {
    final l = context.l10n;
    final code = TextEditingController(text: skill?.code ?? '');
    final name = TextEditingController(text: skill?.name ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(skill == null ? l.planningAddSkill : l.edit),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('skill-code'),
              controller: code,
              decoration: InputDecoration(labelText: l.code),
            ),
            TextField(
              key: const ValueKey('skill-name'),
              controller: name,
              decoration: InputDecoration(labelText: l.name),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            key: const ValueKey('save-skill'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.save),
          ),
        ],
      ),
    );
    final input = SkillInput(code: code.text.trim(), name: name.text.trim());
    code.dispose();
    name.dispose();
    if (ok != true || !mounted) return;
    try {
      if (skill == null) {
        await _api.createSkill(body: input);
      } else {
        await _api.updateSkill(id: skill.id, body: input);
      }
      await _reloadSkills();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(errorMessage(e))));
      }
    }
  }

  Future<void> _saveTechnician(String userId) async {
    final levels = _levels[userId]!;
    try {
      await _api.setUserSkills(
        id: userId,
        body: UserSkillsInput(
          skills: [
            for (final e in levels.entries)
              UserSkillInput(skillId: e.key, level: e.value),
          ],
        ),
      );
      widget.onChanged();
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
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Text(l.planningSkills, style: theme.textTheme.titleMedium),
            const Spacer(),
            FilledButton.icon(
              key: const ValueKey('add-skill'),
              icon: const Icon(AppIcons.add),
              label: Text(l.planningAddSkill),
              onPressed: _edit,
            ),
          ],
        ),
        for (final s in _skills)
          ListTile(
            key: ValueKey('skill-${s.id}'),
            title: Text(s.name),
            subtitle: Text(s.code),
            onTap: () => _edit(s),
            trailing: IconButton(
              tooltip: l.remove,
              icon: const Icon(AppIcons.delete),
              onPressed: () async {
                await _api.deleteSkill(id: s.id);
                for (final m in _levels.values) {
                  m.remove(s.id);
                }
                await _reloadSkills();
              },
            ),
          ),
        const Divider(height: 32),
        Text(l.planningTechnicianSkills, style: theme.textTheme.titleMedium),
        for (final t in widget.board.technicians)
          ExpansionTile(
            title: Text(t.displayName),
            subtitle: Text(
              [
                for (final s in _skills)
                  if (_levels[t.userId]!.containsKey(s.id)) s.code,
              ].join(' · '),
            ),
            children: [
              for (final s in _skills)
                ListTile(
                  dense: true,
                  title: Text(s.name),
                  trailing: DropdownButton<int?>(
                    value: _levels[t.userId]![s.id],
                    hint: const Text('–'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('–')),
                      for (var n = 1; n <= 3; n++)
                        DropdownMenuItem(
                          value: n,
                          child: Text(l.planningSkillLevel(n)),
                        ),
                    ],
                    onChanged: (v) {
                      setState(
                        () => v == null
                            ? _levels[t.userId]!.remove(s.id)
                            : _levels[t.userId]![s.id] = v,
                      );
                      _saveTechnician(t.userId);
                    },
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
