import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/actions.dart';
import '../../shared/app_icons.dart';

final packagingCategoriesProvider = FutureProvider<List<PackagingCategory>>(
  (ref) => ref.watch(apiProvider).products.listPackaging(),
);

/// Lists packaging categories and lets product managers add or change them. A category that
/// requires a shipping quote makes quotations with its products wait for logistics.
class PackagingDialog extends ConsumerWidget {
  const PackagingDialog({super.key});

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, [
    PackagingCategory? c,
  ]) async {
    final code = TextEditingController(text: c?.code);
    final name = TextEditingController(text: c?.name);
    final description = TextEditingController(text: c?.description);
    var requires = c?.requiresShippingQuote ?? false;
    var active = c?.active ?? true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(c == null ? context.l10n.newPackagingCategory : c.code),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: code,
                    decoration: InputDecoration(labelText: context.l10n.code),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: name,
                    decoration: InputDecoration(labelText: context.l10n.name),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: description,
                    decoration: InputDecoration(
                      labelText: context.l10n.description,
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(context.l10n.requiresShippingQuote),
                    value: requires,
                    onChanged: (v) => setState(() => requires = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(context.l10n.active),
                    value: active,
                    onChanged: (v) => setState(() => active = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.l10n.save),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final body = PackagingCategoryInput(
      code: code.text.trim(),
      name: name.text.trim(),
      description: description.text.trim(),
      requiresShippingQuote: requires,
      active: active,
    );
    final api = ref.read(apiProvider).products;
    await runAction(
      context,
      () => c == null
          ? api.createPackaging(body: body)
          : api.updatePackaging(id: c.id, body: body),
    );
    ref.invalidate(packagingCategoriesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(packagingCategoriesProvider);
    final canWrite = can(ref, 'products.write');
    return AlertDialog(
      title: Text(context.l10n.packagingCategories),
      content: SizedBox(
        width: 520,
        child: categories.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text(errorMessage(e)),
          data: (list) => ListView(
            shrinkWrap: true,
            children: [
              for (final c in list)
                ListTile(
                  title: Text('${c.code} · ${c.name}'),
                  subtitle: Text(
                    [
                      context.l10n.productCount(c.productCount),
                      if (c.requiresShippingQuote)
                        context.l10n.requiresShippingQuote,
                      if (!c.active) context.l10n.inactive,
                    ].join(' · '),
                  ),
                  trailing: canWrite
                      ? IconButton(
                          tooltip: context.l10n.edit,
                          icon: const Icon(AppIcons.edit),
                          onPressed: () => _edit(context, ref, c),
                        )
                      : null,
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (canWrite)
          TextButton.icon(
            onPressed: () => _edit(context, ref),
            icon: const Icon(AppIcons.add),
            label: Text(context.l10n.newPackagingCategory),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.close),
        ),
      ],
    );
  }
}
