import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../shared/actions.dart';
import '../../l10n/l10n.dart';
import '../../shared/app_icons.dart';

final familiesProvider = FutureProvider<List<ProductFamily>>(
  (ref) => ref.watch(apiProvider).products.listFamilies(),
);

/// Lists product families and lets product managers add or rename them.
class FamiliesDialog extends ConsumerWidget {
  const FamiliesDialog({super.key});

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, [
    ProductFamily? f,
  ]) async {
    final code = TextEditingController(text: f?.code);
    final name = TextEditingController(text: f?.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(f == null ? context.l10n.newFamily : f.code),
        content: Column(
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
          ],
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
    );
    if (ok != true || !context.mounted) return;
    final body = ProductFamilyInput(
      code: code.text.trim(),
      name: name.text.trim(),
    );
    final api = ref.read(apiProvider).products;
    await runAction(
      context,
      () => f == null
          ? api.createFamily(body: body)
          : api.updateFamily(id: f.id, body: body),
    );
    ref.invalidate(familiesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final families = ref.watch(familiesProvider);
    final canWrite =
        ref.watch(meProvider).value?.permissions.contains('products.write') ??
        false;
    return AlertDialog(
      title: Text(context.l10n.productFamilies),
      content: SizedBox(
        width: 480,
        child: families.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text(errorMessage(e)),
          data: (list) => ListView(
            shrinkWrap: true,
            children: [
              for (final f in list)
                ListTile(
                  title: Text('${f.code} · ${f.name}'),
                  subtitle: Text(context.l10n.productCount(f.productCount)),
                  trailing: canWrite
                      ? IconButton(
                          tooltip: context.l10n.edit,
                          icon: const Icon(AppIcons.edit),
                          onPressed: () => _edit(context, ref, f),
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
            label: Text(context.l10n.newFamily),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.close),
        ),
      ],
    );
  }
}
