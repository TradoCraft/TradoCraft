import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/actions.dart';
import 'kb_common.dart';
import '../../shared/app_icons.dart';

/// Categories of the knowledge base (one level of sub-categories), with a name per language.
class KbCategoriesPage extends ConsumerWidget {
  const KbCategoriesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final canAdmin =
        ref.watch(meProvider).value?.permissions.contains('kb.admin') ?? false;
    final lang = Localizations.localeOf(context).languageCode;
    final cats = ref.watch(kbCategoriesProvider);

    Future<void> edit([Category? c]) async {
      final saved = await showDialog<bool>(
        context: context,
        builder: (_) => _CategoryDialog(category: c, all: cats.value ?? []),
      );
      if (saved == true) ref.invalidate(kbCategoriesProvider);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            IconButton(
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: () =>
                  context.canPop() ? context.pop() : context.go('/kb'),
              icon: const Icon(AppIcons.arrowBack),
            ),
            Text(
              l.kbManageCategories,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const Spacer(),
            if (canAdmin)
              FilledButton.icon(
                onPressed: edit,
                icon: const Icon(AppIcons.add),
                label: Text(l.kbNewCategory),
              ),
          ],
        ),
        const SizedBox(height: 8),
        cats.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text(errorMessage(e)),
          data: (all) => Column(
            children: [
              for (final (c, label) in categoryTree(all, lang))
                Card(
                  key: ValueKey('category-${c.id}'),
                  child: ListTile(
                    contentPadding: EdgeInsets.only(
                      left: c.parentId == null ? 16 : 40,
                      right: 16,
                    ),
                    title: Text(label),
                    subtitle: Text(
                      [
                        '${c.entryCount}',
                        if (!c.active) l.inactive,
                        c.names.map((n) => n.language.toUpperCase()).join(' '),
                      ].join(' · '),
                    ),
                    onTap: canAdmin ? () => edit(c) : null,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CategoryDialog extends ConsumerStatefulWidget {
  const _CategoryDialog({this.category, required this.all});
  final Category? category;
  final List<Category> all;

  @override
  ConsumerState<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends ConsumerState<_CategoryDialog> {
  late final c = widget.category;
  late final _names = {
    for (final code in languageCodes)
      code: TextEditingController(
        text: c?.names.where((n) => n.language == code).firstOrNull?.name,
      ),
  };
  late final _order = TextEditingController(text: '${c?.sortOrder ?? 0}');
  late String? _parent = c?.parentId;
  late bool _active = c?.active ?? true;
  String? _error;

  @override
  void dispose() {
    for (final t in _names.values) {
      t.dispose();
    }
    _order.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final input = CategoryInput(
      parentId: _parent,
      sortOrder: int.tryParse(_order.text.trim()) ?? 0,
      active: _active,
      names: [
        for (final code in languageCodes)
          if (_names[code]!.text.trim().isNotEmpty)
            CategoryName(language: code, name: _names[code]!.text.trim()),
      ],
    );
    try {
      final api = ref.read(apiProvider).kb;
      if (c == null) {
        await api.createKbCategory(body: input);
      } else {
        await api.updateKbCategory(id: c!.id, body: input);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = errorMessage(e));
    }
  }

  Future<void> _delete() async {
    final ok = await runAction(context, () async {
      await ref.read(apiProvider).kb.deleteKbCategory(id: c!.id);
    });
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    final parents = widget.all.where(
      (p) => p.parentId == null && p.id != c?.id,
    );
    return AlertDialog(
      title: Text(c == null ? l.kbNewCategory : pickName(c!.names, lang)),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.kbCategoryNames),
              for (final code in languageCodes)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextField(
                    key: ValueKey('name-$code'),
                    controller: _names[code],
                    decoration: InputDecoration(
                      labelText: languageName(code),
                      isDense: true,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: _parent,
                decoration: InputDecoration(labelText: l.kbMainCategory),
                items: [
                  DropdownMenuItem(value: null, child: Text(l.kbNoCategory)),
                  for (final p in parents)
                    DropdownMenuItem(
                      value: p.id,
                      child: Text(pickName(p.names, lang)),
                    ),
                ],
                onChanged: (v) => setState(() => _parent = v),
              ),
              TextField(
                controller: _order,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: l.kbSortOrder),
              ),
              CheckboxListTile(
                value: _active,
                title: Text(l.active),
                onChanged: (v) => setState(() => _active = v ?? true),
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (c != null) TextButton(onPressed: _delete, child: Text(l.kbDelete)),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(onPressed: _save, child: Text(l.save)),
      ],
    );
  }
}
