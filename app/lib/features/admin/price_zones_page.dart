import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/actions.dart';
import '../tutorial/targets.dart';

/// Price zone management: list, create, edit and delete (the server refuses deleting a zone in use).
class PriceZonesPage extends ConsumerWidget {
  const PriceZonesPage({super.key});

  /// Opens the create/edit dialog and refreshes the list when something was saved.
  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, [
    PriceZone? z,
  ]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => PriceZoneDialog(zone: z),
    );
    if (saved == true && context.mounted) ref.invalidate(priceZonesProvider);
  }

  /// Asks for confirmation, deletes the zone (the server refuses a zone in use) and refreshes.
  Future<void> _delete(BuildContext context, WidgetRef ref, PriceZone z) async {
    final l = context.l10n;
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.delete),
        content: Text(l.deletePriceZoneConfirm(z.code)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            key: const ValueKey('zone-delete-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.delete),
          ),
        ],
      ),
    );
    if (sure != true || !context.mounted) return;
    final ok = await runAction(
      context,
      () => ref.read(apiProvider).products.deletePriceZone(id: z.id),
      success: l.priceZoneDeleted,
    );
    if (ok && context.mounted) ref.invalidate(priceZonesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final zones = ref.watch(priceZonesProvider);
    final canWrite = can(ref, 'prices.write');
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l.adminPriceZones,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            if (canWrite)
              TutorialTarget(id: 'zone-new', child: FilledButton.icon(
                key: const ValueKey('zone-new'),
                onPressed: () => _edit(context, ref),
                icon: const Icon(Icons.add),
                label: Text(l.newPriceZone),
              )),
          ],
        ),
        const SizedBox(height: 8),
        zones.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Row(
            children: [
              Expanded(child: Text(errorMessage(e))),
              TextButton(
                key: const ValueKey('zone-retry'),
                onPressed: () => ref.invalidate(priceZonesProvider),
                child: Text(l.retry),
              ),
            ],
          ),
          data: (list) => list.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(l.noPriceZones),
                )
              : Column(
                  children: [
                    for (final z in list)
                      ListTile(
                        key: ValueKey('zone-${z.code}'),
                        title: Text('${z.code}  ${z.name}'),
                        subtitle: Text('${l.sortOrder}: ${z.sortOrder}'),
                        trailing: canWrite
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    key: ValueKey('zone-edit-${z.code}'),
                                    tooltip: l.edit,
                                    icon: const Icon(Icons.edit_outlined),
                                    onPressed: () => _edit(context, ref, z),
                                  ),
                                  IconButton(
                                    key: ValueKey('zone-del-${z.code}'),
                                    tooltip: l.delete,
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () => _delete(context, ref, z),
                                  ),
                                ],
                              )
                            : null,
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Create ([zone] null) or edit dialog of a price zone; pops true when saved.
class PriceZoneDialog extends ConsumerStatefulWidget {
  const PriceZoneDialog({super.key, this.zone});
  final PriceZone? zone;

  @override
  ConsumerState<PriceZoneDialog> createState() => _PriceZoneDialogState();
}

class _PriceZoneDialogState extends ConsumerState<PriceZoneDialog> {
  late final _code = TextEditingController(text: widget.zone?.code);
  late final _name = TextEditingController(text: widget.zone?.name);
  late final _sort = TextEditingController(
    text: '${widget.zone?.sortOrder ?? 0}',
  );
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _sort.dispose();
    super.dispose();
  }

  /// Validates the form and saves it; the dialog stays open on invalid input or a server error.
  Future<void> _save() async {
    final l = context.l10n;
    if (_code.text.trim().isEmpty || _name.text.trim().isEmpty) {
      setState(() => _error = l.codeNameRequired);
      return;
    }
    final sort = int.tryParse(_sort.text.trim());
    if (sort == null) {
      setState(() => _error = l.sortOrderInvalid);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final body = PriceZoneInput(
      code: _code.text.trim(),
      name: _name.text.trim(),
      sortOrder: sort,
    );
    final products = ref.read(apiProvider).products;
    final z = widget.zone;
    final ok = await runAction(context, () async {
      if (z == null) {
        await products.createPriceZone(body: body);
      } else {
        await products.updatePriceZone(id: z.id, body: body);
      }
    }, success: l.saved);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(widget.zone == null ? l.newPriceZone : l.editPriceZone),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('zone-code'),
              controller: _code,
              autofocus: true,
              decoration: InputDecoration(labelText: l.code),
            ),
            TextField(
              key: const ValueKey('zone-name'),
              controller: _name,
              decoration: InputDecoration(labelText: l.name),
            ),
            TextField(
              key: const ValueKey('zone-sort'),
              controller: _sort,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: l.sortOrder),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
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
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: Text(l.cancel),
        ),
        TutorialTarget(id: 'zone-form-save', child: FilledButton(
          key: const ValueKey('zone-save'),
          onPressed: _busy ? null : _save,
          child: Text(l.save),
        )),
      ],
    );
  }
}
