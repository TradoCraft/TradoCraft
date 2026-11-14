import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/api.dart';
import '../../../l10n/l10n.dart';
import '../../../shared/app_icons.dart';
import 'common.dart';
import 'draft.dart';
import 'editor_state.dart';
import 'fields_tab.dart';
import 'general_tabs.dart';
import 'logic_tabs.dart';
import 'tables_tab.dart';

String tabLabel(AppLocalizations l10n, EditorTab t) => switch (t) {
  EditorTab.general => l10n.cfgbTabGeneral,
  EditorTab.fields => l10n.cfgbTabFields,
  EditorTab.tables => l10n.cfgbTabTables,
  EditorTab.computed => l10n.cfgbTabComputed,
  EditorTab.outputs => l10n.cfgbTabOutputs,
  EditorTab.validations => l10n.cfgbTabValidations,
  EditorTab.test => l10n.cfgbTabTest,
  EditorTab.transfer => l10n.cfgbTabTransfer,
};

/// Edits one revision of a configurator. A draft is edited and saved as a whole (PUT); the
/// problems the server finds are listed with their location and lead there when clicked. Active
/// and obsolete revisions are shown read-only, with "new draft from this revision".
class RevisionEditorScreen extends ConsumerStatefulWidget {
  const RevisionEditorScreen({super.key, required this.id});
  final String id;

  @override
  ConsumerState<RevisionEditorScreen> createState() =>
      _RevisionEditorScreenState();
}

class _RevisionEditorScreenState extends ConsumerState<RevisionEditorScreen>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: EditorTab.values.length, vsync: this)
    ..index = EditorTab.fields.index;

  RevisionEditorNotifier get _n =>
      ref.read(revisionEditorProvider(widget.id).notifier);

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) _n.setTab(EditorTab.values[_tabs.index]);
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _save() async {
    try {
      final errors = await _n.save();
      if (!mounted) return;
      _snack(
        errors.isEmpty
            ? context.l10n.cfgbSavedValid
            : context.l10n.cfgbSavedWithProblems(errors.length),
      );
    } catch (e) {
      _snack(errorMessage(e));
    }
  }

  Future<void> _activate() async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.cfgbActivate),
        content: Text(l10n.cfgbActivateConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.cfgbActivate),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final message = await _n.activate();
      if (!mounted) return;
      final s = ref.read(revisionEditorProvider(widget.id));
      if (s.errors.isNotEmpty) {
        _snack(l10n.cfgbActivateRefused(s.errors.length));
        _showProblems();
      } else if (message != null) {
        // Refused for another reason than problems in the definition.
        _snack(message);
      } else {
        _snack(l10n.cfgbActivated);
      }
    } catch (e) {
      _snack(errorMessage(e));
    }
  }

  Future<void> _newDraft() async {
    final r = ref.read(revisionEditorProvider(widget.id)).revision!;
    try {
      final draft = await ref
          .read(apiProvider)
          .configurator
          .createRevision(
            id: r.modelId,
            body: NewRevisionInput(copyFrom: r.id),
          );
      if (mounted) {
        context.pushReplacement('/configurator/builder/revisions/${draft.id}');
      }
    } catch (e) {
      _snack(errorMessage(e));
    }
  }

  void _showProblems() {
    final s = ref.read(revisionEditorProvider(widget.id));
    if (s.errors.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => ProblemsSheet(
        id: widget.id,
        onSelect: (path) {
          Navigator.pop(context);
          _n.goTo(path);
        },
      ),
    );
  }

  Future<bool> _confirmLeave() async {
    final l10n = context.l10n;
    final r = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.cfgbUnsavedTitle),
        content: Text(l10n.cfgbUnsavedText),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'stay'),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: const ValueKey('discard'),
            onPressed: () => Navigator.pop(context, 'discard'),
            child: Text(l10n.cfgbDiscard),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'save'),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    if (r == 'save') {
      await _save();
      return !ref.read(revisionEditorProvider(widget.id)).dirty;
    }
    return r == 'discard';
  }

  Future<void> _back() async {
    final s = ref.read(revisionEditorProvider(widget.id));
    if (s.dirty && !await _confirmLeave()) return;
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(
        s.revision == null
            ? '/configurator/builder'
            : '/configurator/builder/models/${s.revision!.modelId}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(revisionEditorProvider(widget.id));
    final l10n = context.l10n;
    final theme = Theme.of(context);
    // An error navigation moves the tab bar along.
    ref.listen(revisionEditorProvider(widget.id).select((s) => s.tab), (_, t) {
      if (_tabs.index != t.index) _tabs.animateTo(t.index);
    });
    if (s.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final r = s.revision;
    if (r == null || s.draft == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(s.loadError ?? ''),
              const SizedBox(height: 12),
              FilledButton(onPressed: _n.load, child: Text(l10n.retry)),
            ],
          ),
        ),
      );
    }
    final errorCount = s.errors.length;
    Widget tab(EditorTab t) => switch (t) {
      EditorTab.general => GeneralTab(id: widget.id),
      EditorTab.fields => FieldsTab(id: widget.id),
      EditorTab.tables => TablesTab(id: widget.id),
      EditorTab.computed => ComputedTab(id: widget.id),
      EditorTab.outputs => OutputsTab(id: widget.id),
      EditorTab.validations => ValidationsTab(id: widget.id),
      EditorTab.test => TestTab(id: widget.id),
      EditorTab.transfer => TransferTab(id: widget.id),
    };
    int tabErrors(EditorTab t) =>
        s.errors.where((e) => locate(e.path).tab == t).length;

    return PopScope(
      canPop: !s.dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  IconButton(
                    key: const ValueKey('editor-back'),
                    tooltip: MaterialLocalizations.of(context)
                        .backButtonTooltip,
                    onPressed: _back,
                    icon: const Icon(AppIcons.arrowBack),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.modelName, style: theme.textTheme.titleLarge),
                      Text(
                        '${r.modelCode} · ${l10n.cfgRevision(r.revision)} · ${revisionStatusLabel(l10n, r.status)}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                  if (s.dirty)
                    Text(l10n.cfgUnsaved, style: theme.textTheme.bodySmall),
                  ActionChip(
                    key: const ValueKey('problems'),
                    avatar: Icon(
                      errorCount == 0 ? AppIcons.checkCircle : AppIcons.error,
                      size: 18,
                      color: errorCount == 0
                          ? theme.colorScheme.primary
                          : theme.colorScheme.error,
                    ),
                    label: Text(
                      errorCount == 0
                          ? l10n.cfgbNoProblems
                          : l10n.cfgbProblems(errorCount),
                    ),
                    onPressed: errorCount == 0 ? null : _showProblems,
                  ),
                  if (!s.readOnly) ...[
                    OutlinedButton.icon(
                      key: const ValueKey('save-draft'),
                      onPressed: s.busy ? null : _save,
                      icon: const Icon(AppIcons.save),
                      label: Text(l10n.save),
                    ),
                    FilledButton.icon(
                      key: const ValueKey('activate'),
                      onPressed: s.busy ? null : _activate,
                      icon: const Icon(AppIcons.verified),
                      label: Text(l10n.cfgbActivate),
                    ),
                  ] else
                    FilledButton.tonalIcon(
                      onPressed: s.busy ? null : _newDraft,
                      icon: const Icon(AppIcons.copy),
                      label: Text(l10n.cfgbNewDraftFromThis),
                    ),
                ],
              ),
            ),
            SizedBox(
              height: 2,
              child: s.busy
                  ? const LinearProgressIndicator(minHeight: 2)
                  : const SizedBox.shrink(),
            ),
            TabBar(
              controller: _tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                for (final t in EditorTab.values)
                  Tab(
                    key: ValueKey('tab-${t.name}'),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(tabLabel(l10n, t)),
                        if (tabErrors(t) > 0) ...[
                          const SizedBox(width: 6),
                          Badge(
                            label: Text('${tabErrors(t)}'),
                            backgroundColor: theme.colorScheme.error,
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
            const Divider(height: 1),
            Expanded(
              child: ReadOnlyScope(
                readOnly: s.readOnly,
                child: TabBarView(
                  controller: _tabs,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [for (final t in EditorTab.values) tab(t)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String revisionStatusLabel(AppLocalizations l10n, String status) =>
    switch (status) {
      'draft' => l10n.cfgbStatusDraft,
      'active' => l10n.cfgbStatusActive,
      _ => l10n.cfgbStatusObsolete,
    };

/// The problems of the saved draft with where they are; a tap leads there.
class ProblemsSheet extends ConsumerWidget {
  const ProblemsSheet({super.key, required this.id, required this.onSelect});
  final String id;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(revisionEditorProvider(id));
    final l10n = context.l10n;
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              l10n.cfgbProblems(s.errors.length),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          for (final e in s.errors)
            ListTile(
              key: ValueKey('problem-${e.path}'),
              leading: Icon(
                AppIcons.error,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(e.message),
              subtitle: Text(
                '${tabLabel(l10n, locate(e.path).tab)} · ${e.path}',
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              onTap: () => onSelect(e.path),
            ),
        ],
      ),
    );
  }
}
