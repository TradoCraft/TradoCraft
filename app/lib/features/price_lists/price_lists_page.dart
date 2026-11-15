import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/actions.dart';
import '../../shared/app_icons.dart';
import '../../shared/format.dart';
import 'price_lists_api.dart';

/// Price lists: the list of lists with create, edit and delete; a list opens in the editor.
class PriceListsPage extends ConsumerWidget {
  const PriceListsPage({super.key});

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, [
    PriceList? list,
  ]) async {
    final saved = await showDialog<PriceList>(
      context: context,
      builder: (_) => PriceListDialog(list: list),
    );
    if (saved != null && context.mounted) {
      ref.invalidate(priceListsProvider);
      ref.invalidate(priceListProvider(saved.id));
      // A new list goes straight to the editor: it is empty.
      if (list == null) context.go('/price-lists/${saved.id}');
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, PriceList p) async {
    final l = context.l10n;
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.delete),
        content: Text(l.plDeleteConfirm(p.code)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            key: const ValueKey('pl-delete-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.delete),
          ),
        ],
      ),
    );
    if (sure != true || !context.mounted) return;
    final ok = await runAction(
      context,
      () => ref.read(apiProvider).products.deletePriceList(id: p.id),
      success: l.plDeleted,
    );
    if (ok && context.mounted) ref.invalidate(priceListsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final lists = ref.watch(priceListsProvider);
    final canWrite = can(ref, 'price_lists.write');
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l.plTitle,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            if (canWrite)
              FilledButton.icon(
                key: const ValueKey('pl-new'),
                onPressed: () => _edit(context, ref),
                icon: const Icon(AppIcons.add),
                label: Text(l.plNew),
              ),
          ],
        ),
        const SizedBox(height: 8),
        lists.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Row(
            children: [
              Expanded(child: Text(errorMessage(e))),
              TextButton(
                key: const ValueKey('pl-retry'),
                onPressed: () => ref.invalidate(priceListsProvider),
                child: Text(l.retry),
              ),
            ],
          ),
          data: (items) => items.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(l.plNone),
                )
              : Column(
                  children: [
                    for (final p in items)
                      ListTile(
                        key: ValueKey('pl-${p.code}'),
                        title: Text('${p.code}  ${p.name}'),
                        subtitle: Text(
                          [
                            for (final z in p.zones)
                              '${z.priceZoneCode} ${z.languages.map((c) => c.toUpperCase()).join(' ')}',
                            '${l.validFrom} ${date(p.validFrom)}',
                            l.plProductCount(p.itemCount),
                          ].join(' · '),
                        ),
                        onTap: () => context.go('/price-lists/${p.id}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              key: ValueKey('pl-open-${p.code}'),
                              tooltip: l.plOpen,
                              icon: const Icon(AppIcons.accountTree),
                              onPressed: () => context.go('/price-lists/${p.id}'),
                            ),
                            if (canWrite) ...[
                              IconButton(
                                key: ValueKey('pl-edit-${p.code}'),
                                tooltip: l.edit,
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => _edit(context, ref, p),
                              ),
                              IconButton(
                                key: ValueKey('pl-del-${p.code}'),
                                tooltip: l.delete,
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _delete(context, ref, p),
                              ),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Create ([list] null) or edit dialog of a price list; pops the saved [PriceList].
class PriceListDialog extends ConsumerStatefulWidget {
  const PriceListDialog({super.key, this.list});
  final PriceList? list;

  @override
  ConsumerState<PriceListDialog> createState() => _PriceListDialogState();
}

class _PriceListDialogState extends ConsumerState<PriceListDialog> {
  late final _code = TextEditingController(text: widget.list?.code);
  late final _name = TextEditingController(text: widget.list?.name);
  late DateTime _validFrom = widget.list?.validFrom ?? DateTime.now();
  late bool _showLogo = widget.list?.settings.showLogo ?? true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _validFrom,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _validFrom = d);
  }

  Future<void> _save() async {
    final l = context.l10n;
    if (_code.text.trim().isEmpty || _name.text.trim().isEmpty) {
      setState(() => _error = l.codeNameRequired);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final old = widget.list?.settings;
    final body = PriceListInput(
      code: _code.text.trim(),
      name: _name.text.trim(),
      validFrom: DateTime(_validFrom.year, _validFrom.month, _validFrom.day),
      settings: PriceListSettings(
        accentColor: old?.accentColor ?? '#1f4e79',
        currencySymbol: old?.currencySymbol ?? '',
        footerText: old?.footerText ?? '',
        showUnit: old?.showUnit ?? true,
        showLogo: _showLogo,
      ),
    );
    final products = ref.read(apiProvider).products;
    final existing = widget.list;
    PriceList? saved;
    final ok = await runAction(context, () async {
      saved = existing == null
          ? await products.createPriceList(body: body)
          : await products.updatePriceList(id: existing.id, body: body);
    }, success: l.saved);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, saved);
    } else {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(widget.list == null ? l.plNew : l.plEdit),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const ValueKey('pl-code'),
                controller: _code,
                autofocus: true,
                decoration: InputDecoration(labelText: l.code),
              ),
              TextField(
                key: const ValueKey('pl-name'),
                controller: _name,
                decoration: InputDecoration(labelText: l.name),
              ),
              const SizedBox(height: 8),
              ListTile(
                key: const ValueKey('pl-valid-from'),
                contentPadding: EdgeInsets.zero,
                title: Text('${l.validFrom}: ${date(_validFrom)}'),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: _pickDate,
              ),
              SwitchListTile(
                key: const ValueKey('pl-show-logo'),
                contentPadding: EdgeInsets.zero,
                title: Text(l.plShowLogo),
                value: _showLogo,
                onChanged: (v) => setState(() => _showLogo = v),
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
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('pl-save'),
          onPressed: _busy ? null : _save,
          child: Text(l.save),
        ),
      ],
    );
  }
}
