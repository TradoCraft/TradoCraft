import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/api.dart';
import '../../../l10n/l10n.dart';
import '../../../shared/actions.dart';
import '../../../shared/app_icons.dart';
import 'import_wizard.dart';

/// Step 3: one row per file column with the field it fills, saved mappings and the rules that
/// block continuing (the key column must be mapped, a field only once).
class MappingEditor extends ConsumerWidget {
  const MappingEditor({super.key});

  // Value of the "Ignore" entry: a dropdown cannot select a null value.
  static const ignore = '';

  Future<void> _openSaved(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => const _SavedMappingsDialog(),
  );

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final s = ref.read(importWizardProvider);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(initial: s.proposedFrom ?? ''),
    );
    if (name == null || name.isEmpty || !context.mounted) return;
    final exists = s.saved.any((m) => m.name == name);
    if (exists) {
      final sure = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l.impOverwriteTitle),
          content: Text(l.impOverwriteBody(name)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.cancel),
            ),
            FilledButton(
              key: const ValueKey('imp-overwrite-confirm'),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.impOverwriteAction),
            ),
          ],
        ),
      );
      if (sure != true || !context.mounted) return;
    }
    await runAction(
      context,
      () => ref.read(importWizardProvider.notifier).saveMapping(name),
      success: l.impMappingSaved(name),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final s = ref.watch(importWizardProvider);
    final wizard = ref.read(importWizardProvider.notifier);
    final entity = s.entity!;
    final preview = s.preview!;
    final check = s.check!;
    final scheme = Theme.of(context).colorScheme;
    Widget dropdown(int i) {
      final field = s.fields[i];
      final dup = field != null && check.duplicates.contains(field);
      return DropdownButtonFormField<String>(
        key: ValueKey('imp-field-$i-$field'),
        isExpanded: true,
        initialValue: field ?? ignore,
        decoration: InputDecoration(
          labelText: l.impColField,
          isDense: true,
          errorText: dup ? l.impDuplicateField(field) : null,
          errorMaxLines: 3,
        ),
        items: [
          DropdownMenuItem(
            value: ignore,
            child: Text(
              l.impIgnore,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
          for (final c in entity.columns)
            DropdownMenuItem(
              value: c.name,
              child: Text(
                [
                  c.name,
                  if (c.name == entity.keyColumn) '(${l.impKeyBadge})',
                  if (c.requiredValue) '*',
                ].join(' '),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (v) =>
            wizard.setField(i, (v == null || v == ignore) ? null : v),
      );
    }

    String sample(int i) {
      for (final r in preview.rows) {
        if (i < r.length && r[i].trim().isNotEmpty) return r[i];
      }
      return '';
    }

    Widget fileColumn(int i) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          preview.columns[i],
          style: Theme.of(context).textTheme.titleSmall,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          sample(i).isEmpty ? '—' : '${l.impColSample}: ${sample(i)}',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('imp-saved-mappings'),
              onPressed: () => _openSaved(context),
              icon: const Icon(AppIcons.bookmark),
              label: Text(l.impMappingsMenu),
            ),
            OutlinedButton.icon(
              key: const ValueKey('imp-save-mapping'),
              onPressed: () => _save(context, ref),
              icon: const Icon(AppIcons.save),
              label: Text(l.impSaveMapping),
            ),
          ],
        ),
        if (s.savedError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              errorMessage(s.savedError!),
              style: TextStyle(color: scheme.error),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          s.proposedFrom != null
              ? l.impProposalSaved(s.proposedFrom!)
              : l.impProposalByName,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth >= 640;
            return Column(
              children: [
                for (var i = 0; i < preview.columns.length; i++)
                  Padding(
                    key: ValueKey('imp-row-$i'),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 3, child: fileColumn(i)),
                              const SizedBox(width: 12),
                              Expanded(flex: 3, child: dropdown(i)),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              fileColumn(i),
                              const SizedBox(height: 6),
                              dropdown(i),
                            ],
                          ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        Text(
          '* ${l.impRequiredNew}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        if (check.keyMissing)
          _Note(
            icon: AppIcons.error,
            color: scheme.error,
            text: l.impKeyMissing(entity.keyColumn),
          ),
        for (final f in check.duplicates)
          _Note(
            icon: AppIcons.error,
            color: scheme.error,
            text: l.impDuplicateField(f),
          ),
        if (check.unmappedRequired.isNotEmpty)
          _Note(
            icon: AppIcons.warningAmber,
            color: scheme.tertiary,
            text: l.impUnmappedRequired(check.unmappedRequired.join(', ')),
          ),
        if (check.unmapped.isEmpty)
          _Note(
            icon: AppIcons.checkCircle,
            color: scheme.primary,
            text: l.impAllMapped,
          )
        else
          _Note(
            icon: AppIcons.info,
            color: scheme.onSurfaceVariant,
            text: l.impUnmapped(check.unmapped.join(', ')),
          ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    ),
  );
}

/// Asks for the name to save the mapping under.
class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.initial});
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _name = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.impSaveMapping),
      content: TextField(
        key: const ValueKey('imp-mapping-name'),
        controller: _name,
        autofocus: true,
        decoration: InputDecoration(labelText: l.impMappingName),
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('imp-mapping-name-ok'),
          onPressed: () => Navigator.pop(context, _name.text.trim()),
          child: Text(l.save),
        ),
      ],
    );
  }
}

/// The saved mappings of the entity: tap one to take it, or delete it.
class _SavedMappingsDialog extends ConsumerWidget {
  const _SavedMappingsDialog();

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    ImportMapping m,
  ) async {
    final l = context.l10n;
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.delete),
        content: Text(l.impDeleteMappingConfirm(m.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            key: const ValueKey('imp-delete-mapping-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.delete),
          ),
        ],
      ),
    );
    if (sure != true || !context.mounted) return;
    await runAction(
      context,
      () => ref.read(importWizardProvider.notifier).deleteMapping(m),
      success: l.impMappingDeleted(m.name),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final s = ref.watch(importWizardProvider);
    return AlertDialog(
      title: Text(l.impMappingsMenu),
      content: SizedBox(
        width: 420,
        child: s.savedLoading
            ? const LinearProgressIndicator()
            : s.saved.isEmpty
            ? Text(l.impNoMappings)
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final m in s.saved)
                    ListTile(
                      key: ValueKey('imp-mapping-${m.name}'),
                      contentPadding: EdgeInsets.zero,
                      title: Text(m.name, overflow: TextOverflow.ellipsis),
                      onTap: () {
                        ref.read(importWizardProvider.notifier).useMapping(m);
                        Navigator.pop(context);
                      },
                      trailing: IconButton(
                        key: ValueKey('imp-mapping-delete-${m.name}'),
                        tooltip: l.impDeleteMapping(m.name),
                        icon: const Icon(AppIcons.delete),
                        onPressed: () => _delete(context, ref, m),
                      ),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.close),
        ),
      ],
    );
  }
}
