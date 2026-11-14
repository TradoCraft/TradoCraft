import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/api.dart';
import '../../../l10n/l10n.dart';
import '../../../shared/actions.dart';
import '../../../shared/app_icons.dart';
import '../../../shared/format.dart';
import 'general_tabs.dart';
import 'revision_editor.dart';

/// All configurators of the company (active or not), for designers.
final builderModelsProvider = FutureProvider.autoDispose<List<ModelSummary>>(
  (ref) => ref.watch(apiProvider).configurator.listModels(),
);

final builderModelProvider = FutureProvider.autoDispose.family<Model, String>(
  (ref, id) => ref.watch(apiProvider).configurator.getModel(id: id),
);

/// The configurator designer's start page: the configurators with their active and draft
/// revisions; create one, or import a JSON export.
class BuilderModelsPage extends ConsumerWidget {
  const BuilderModelsPage({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final model = await showDialog<Model>(
      context: context,
      builder: (_) => const NewModelDialog(),
    );
    if (model == null || !context.mounted) return;
    ref.invalidate(builderModelsProvider);
    final draft = model.revisions.where((r) => r.status == 'draft').firstOrNull;
    if (draft != null) {
      await context.push('/configurator/builder/revisions/${draft.id}');
      ref.invalidate(builderModelsProvider);
    }
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final f = await ref.read(jsonPickerProvider)();
    if (f == null || !context.mounted) return;
    Revision? rev;
    await runAction(context, () async {
      final v = jsonDecode(utf8.decode(f.bytes));
      if (v is! Map || !v.containsKey('definition')) {
        throw l10n.cfgbImportNotExport;
      }
      rev = await ref
          .read(apiProvider)
          .configurator
          .importModel(body: ModelExport.fromJson(v.cast<String, Object?>()));
    });
    ref.invalidate(builderModelsProvider);
    if (rev != null && context.mounted) {
      await context.push('/configurator/builder/revisions/${rev!.id}');
      ref.invalidate(builderModelsProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final models = ref.watch(builderModelsProvider);
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(builderModelsProvider),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  icon: const Icon(AppIcons.arrowBack),
                  onPressed: () => context.canPop()
                      ? context.pop()
                      : context.go('/configurator'),
                ),
                Expanded(
                  child: Text(
                    l10n.cfgbDesignTitle,
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('import-model'),
                  onPressed: () => _import(context, ref),
                  icon: const Icon(AppIcons.fileUpload),
                  label: Text(l10n.cfgbImportJson),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  key: const ValueKey('new-model'),
                  onPressed: () => _create(context, ref),
                  icon: const Icon(AppIcons.add),
                  label: Text(l10n.cfgbNewModel),
                ),
              ],
            ),
            const SizedBox(height: 16),
            models.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text(errorMessage(e)),
              data: (list) => list.isEmpty
                  ? Text(l10n.cfgNoModels)
                  : Card(
                      child: Column(
                        children: [
                          for (final m in list)
                            ListTile(
                              key: ValueKey('model-${m.id}'),
                              leading: Icon(
                                m.active
                                    ? AppIcons.dashboardCustomize
                                    : AppIcons.visibilityOff,
                              ),
                              title: Text('${m.name} · ${m.code}'),
                              subtitle: Text(
                                [
                                  if (m.activeRevision != null)
                                    l10n.cfgbActiveRevision(m.activeRevision!),
                                  if (m.draftRevision != null)
                                    l10n.cfgbDraftRevision(m.draftRevision!),
                                  if (!m.active) l10n.cfgbInactive,
                                  date(m.updatedAt.toLocal()),
                                ].join(' · '),
                              ),
                              trailing: m.draftRevisionId == null
                                  ? null
                                  : TextButton(
                                      onPressed: () async {
                                        await context.push(
                                          '/configurator/builder/revisions/${m.draftRevisionId}',
                                        );
                                        // The draft may have been activated meanwhile.
                                        ref.invalidate(builderModelsProvider);
                                      },
                                      child: Text(l10n.cfgbEditDraft),
                                    ),
                              onTap: () async {
                                await context.push(
                                  '/configurator/builder/models/${m.id}',
                                );
                                ref.invalidate(builderModelsProvider);
                              },
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Creates a configurator (code, name, description) with an empty first draft.
class NewModelDialog extends ConsumerStatefulWidget {
  const NewModelDialog({super.key});

  @override
  ConsumerState<NewModelDialog> createState() => _NewModelDialogState();
}

class _NewModelDialogState extends ConsumerState<NewModelDialog> {
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _description = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final m = await ref
          .read(apiProvider)
          .configurator
          .createModel(
            body: NewModelInput(
              code: _code.text.trim(),
              name: _name.text.trim(),
              description: _description.text.trim(),
            ),
          );
      if (mounted) Navigator.pop(context, m);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.cfgbNewModel),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('model-code'),
              controller: _code,
              decoration: InputDecoration(labelText: l10n.code),
            ),
            TextField(
              key: const ValueKey('model-name'),
              controller: _name,
              decoration: InputDecoration(labelText: l10n.name),
            ),
            TextField(
              controller: _description,
              decoration: InputDecoration(labelText: l10n.description),
              maxLines: 3,
              minLines: 1,
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey('create-model'),
          onPressed: _busy ? null : _create,
          child: Text(l10n.cfgbCreate),
        ),
      ],
    );
  }
}

/// One configurator: its settings and its revision history; open a revision, start a new draft
/// from the active one, export a revision.
class ModelPage extends ConsumerWidget {
  const ModelPage({super.key, required this.id});
  final String id;

  Future<void> _newDraft(BuildContext context, WidgetRef ref) async {
    Revision? r;
    await runAction(context, () async {
      r = await ref
          .read(apiProvider)
          .configurator
          .createRevision(id: id, body: const NewRevisionInput());
    });
    ref.invalidate(builderModelProvider(id));
    if (r != null && context.mounted) {
      await context.push('/configurator/builder/revisions/${r!.id}');
      ref.invalidate(builderModelProvider(id));
    }
  }

  Future<void> _export(
    BuildContext context,
    WidgetRef ref,
    RevisionSummary r,
  ) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ex = await ref
          .read(apiProvider)
          .configurator
          .exportRevision(id: r.id);
      final doc = {...ex.toJson(), 'model': ex.model.toJson()};
      final name = '${ex.model.code.toLowerCase()}-r${r.revision}.json';
      final saved = await ref.read(jsonSaverProvider)(
        name,
        utf8.encode(const JsonEncoder.withIndent('  ').convert(doc)),
      );
      if (saved) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.cfgbExported(name))),
        );
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(errorMessage(e))));
    }
  }

  Future<void> _toggleActive(
    BuildContext context,
    WidgetRef ref,
    Model m,
  ) async {
    await runAction(
      context,
      () => ref
          .read(apiProvider)
          .configurator
          .updateModel(
            id: m.id,
            body: ModelUpdate(
              name: m.name,
              description: m.description,
              translations: m.translations,
              productId: m.productId,
              active: !m.active,
            ),
          ),
    );
    ref.invalidate(builderModelProvider(id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final model = ref.watch(builderModelProvider(id));
    return Scaffold(
      body: model.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(errorMessage(e))),
        data: (m) {
          final hasDraft = m.revisions.any((r) => r.status == 'draft');
          final hasActive = m.revisions.any((r) => r.status == 'active');
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: MaterialLocalizations.of(context)
                        .backButtonTooltip,
                    icon: const Icon(AppIcons.arrowBack),
                    onPressed: () => context.canPop()
                        ? context.pop()
                        : context.go('/configurator/builder'),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m.name, style: theme.textTheme.headlineSmall),
                        Text(m.code, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _toggleActive(context, ref, m),
                    icon: Icon(
                      m.active ? AppIcons.visibilityOff : AppIcons.visibility,
                    ),
                    label: Text(
                      m.active
                          ? l10n.cfgbDeactivateModel
                          : l10n.cfgbActivateModel,
                    ),
                  ),
                  if (!hasDraft && hasActive)
                    FilledButton.icon(
                      key: const ValueKey('new-draft'),
                      onPressed: () => _newDraft(context, ref),
                      icon: const Icon(AppIcons.copy),
                      label: Text(l10n.cfgbNewDraft),
                    ),
                ],
              ),
              if (m.description.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(m.description),
                ),
              const SizedBox(height: 16),
              Text(l10n.cfgbRevisions, style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    for (final r in m.revisions)
                      ListTile(
                        key: ValueKey('revision-${r.id}'),
                        leading: Icon(switch (r.status) {
                          'draft' => AppIcons.editNote,
                          'active' => AppIcons.verified,
                          _ => AppIcons.history,
                        }),
                        title: Text(
                          '${l10n.cfgRevision(r.revision)} · ${revisionStatusLabel(l10n, r.status)}',
                        ),
                        subtitle: Text(
                          [
                            if (r.notes.isNotEmpty) r.notes,
                            r.activatedAt != null
                                ? l10n.cfgbActivatedOn(
                                    date(r.activatedAt!.toLocal()),
                                  )
                                : date(r.createdAt.toLocal()),
                          ].join(' · '),
                        ),
                        trailing: IconButton(
                          tooltip: l10n.cfgbExportJson,
                          icon: const Icon(AppIcons.fileDownload),
                          onPressed: () => _export(context, ref, r),
                        ),
                        onTap: () async {
                          await context.push(
                            '/configurator/builder/revisions/${r.id}',
                          );
                          ref.invalidate(builderModelProvider(id));
                        },
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
