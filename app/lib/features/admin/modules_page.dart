import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/actions.dart';
import 'modules_tree.dart';

/// The module catalogue with the company's switches.
final adminModulesProvider = FutureProvider.autoDispose<List<ModuleInfo>>(
  (ref) => ref.watch(apiProvider).core.getModules(),
);

/// Company-wide module switches. The server validates dependencies and answers 422 with a message.
class ModulesPage extends ConsumerStatefulWidget {
  const ModulesPage({super.key});

  @override
  ConsumerState<ModulesPage> createState() => _ModulesPageState();
}

class _ModulesPageState extends ConsumerState<ModulesPage> {
  /// The switches being edited; null until the catalogue has loaded.
  Set<String>? _disabled;
  Set<String> _saved = {};
  bool _saving = false;

  /// Ids of the collapsed tree rows; everything starts expanded.
  final Set<String> _collapsed = {};

  /// Switches a module, cascading along the dependencies, and tells the admin what moved along.
  void _toggle(Map<String, List<String>> requires, String code, bool on) {
    final l = context.l10n;
    final r = toggleModule(requires, _disabled!, code, on);
    setState(() => _disabled = r.disabled);
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    if (r.alsoChanged.isNotEmpty) {
      final names = r.alsoChanged.map(l.moduleName).join(', ');
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            on ? l.moduleAlsoSwitchedOn(names) : l.moduleAlsoSwitchedOff(names),
          ),
        ),
      );
    }
  }

  Set<String> _offIn(List<ModuleInfo> list) => {
    for (final m in list)
      if (!m.enabled) m.code,
  };

  Future<void> _save() async {
    // The "also switches off" note must not queue the result message behind it.
    ScaffoldMessenger.of(context).clearSnackBars();
    setState(() => _saving = true);
    ModulesInput body = ModulesInput(
      disabledModules: _disabled!.toList()..sort(),
    );
    List<ModuleInfo>? result;
    final ok = await runAction(context, () async {
      result = await ref.read(apiProvider).core.setModules(body: body);
    }, success: context.l10n.modulesSaved);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok && result != null) {
      setState(() {
        _saved = _offIn(result!);
        _disabled = {..._saved};
      });
      ref.invalidate(adminModulesProvider);
      // The server filters permissions by module, so the navigation changes with this.
      ref.invalidate(meProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final modules = ref.watch(adminModulesProvider);
    return modules.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(errorMessage(e)),
      ),
      data: (list) {
        if (_disabled == null) {
          _saved = _offIn(list);
          _disabled = {..._saved};
        }
        final off = _disabled!;
        final requires = {for (final m in list) m.code: m.requires};
        final rows = <ModuleTreeNode>[];
        void walk(ModuleTreeNode n) {
          rows.add(n);
          if (_collapsed.contains(n.id)) return;
          n.children.forEach(walk);
        }

        buildModuleTree(requires).forEach(walk);
        final changed = off.length != _saved.length || !off.containsAll(_saved);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l.adminModules,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                FilledButton(
                  onPressed: changed && !_saving ? _save : null,
                  child: Text(l.save),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(l.modulesIntro),
            const SizedBox(height: 8),
            for (final n in rows)
              _ModuleRow(
                node: n,
                on: !off.contains(n.code),
                hasChildren: n.children.isNotEmpty,
                collapsed: _collapsed.contains(n.id),
                enabled: !_saving,
                onToggle: (on) => _toggle(requires, n.code, on),
                onExpand: () => setState(() {
                  if (!_collapsed.remove(n.id)) _collapsed.add(n.id);
                }),
              ),
          ],
        );
      },
    );
  }
}

/// One row of the module tree: expand/collapse button, connector line, and the module's switch with
/// its requirements and an explicit On/Off label.
class _ModuleRow extends StatelessWidget {
  const _ModuleRow({
    required this.node,
    required this.on,
    required this.hasChildren,
    required this.collapsed,
    required this.enabled,
    required this.onToggle,
    required this.onExpand,
  });

  final ModuleTreeNode node;
  final bool on;
  final bool hasChildren;
  final bool collapsed;
  final bool enabled;
  final ValueChanged<bool> onToggle;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final name = l.moduleName(node.code);
    final String? hint;
    if (node.repeat) {
      hint = l.moduleAlsoRequires(
        node.otherRequires.map(l.moduleName).join(', '),
      );
    } else if (node.requires.isNotEmpty) {
      hint = l.moduleRequires(node.requires.map(l.moduleName).join(', '));
    } else {
      hint = null;
    }
    final state = on ? l.moduleOn : l.moduleOff;
    final key = node.repeat
        ? ValueKey('module-${node.code}-under-${node.parent}')
        : ValueKey('module-${node.code}');
    return Semantics(
      label: l.moduleLevel(node.depth + 1),
      child: Padding(
        padding: EdgeInsets.only(left: node.depth * 20.0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: node.depth == 0
                ? null
                : Border(
                    left: BorderSide(color: scheme.outlineVariant, width: 2),
                  ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 48,
                child: hasChildren
                    ? IconButton(
                        key: ValueKey('expand-${node.id}'),
                        tooltip: collapsed
                            ? l.moduleExpand(name)
                            : l.moduleCollapse(name),
                        icon: Icon(
                          collapsed ? Icons.chevron_right : Icons.expand_more,
                        ),
                        onPressed: onExpand,
                      )
                    : null,
              ),
              Expanded(
                child: SwitchListTile(
                  key: key,
                  contentPadding: const EdgeInsets.only(right: 8),
                  title: Text(name),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (hint != null) Text(hint),
                      Text(
                        state,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: on ? scheme.primary : scheme.error,
                        ),
                      ),
                    ],
                  ),
                  thumbIcon: WidgetStateProperty.resolveWith(
                    (s) => Icon(
                      s.contains(WidgetState.selected)
                          ? Icons.check
                          : Icons.close,
                    ),
                  ),
                  value: on,
                  onChanged: enabled ? onToggle : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
