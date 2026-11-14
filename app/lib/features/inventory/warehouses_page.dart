import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/actions.dart';
import '../tutorial/targets.dart';
import 'inventory_common.dart';
import '../../shared/app_icons.dart';

/// Warehouses, service vans and their locations (inventory administrators change them).
class WarehousesPage extends ConsumerWidget {
  const WarehousesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final canAdmin = hasPermission(ref, 'inventory.admin');
    final warehouses = ref.watch(warehousesProvider);
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                IconButton(
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: () =>
                      context.canPop() ? context.pop() : context.go('/stock'),
                  icon: const Icon(AppIcons.arrowBack),
                ),
                Text(
                  l.stockWarehouses,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                if (canAdmin) ...[
                  TutorialTarget(
                    id: 'warehouse-new',
                    child: FilledButton.icon(
                      icon: const Icon(AppIcons.add),
                      label: Text(l.stockNewWarehouse),
                      onPressed: () => _edit(context, ref, null, van: false),
                    ),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(AppIcons.localShipping),
                    label: Text(l.stockNewVan),
                    onPressed: () => _edit(context, ref, null, van: true),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: warehouses.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text(errorMessage(e))),
                data: (list) => list.isEmpty
                    ? Center(child: Text(l.stockNoWarehouses))
                    : ListView(
                        children: [
                          for (final w in list)
                            _WarehouseCard(warehouse: w, canAdmin: canAdmin),
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

Future<void> _edit(
  BuildContext context,
  WidgetRef ref,
  Warehouse? w, {
  required bool van,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) =>
        _WarehouseDialog(warehouse: w, van: w?.kind == 'van' || van),
  );
  if (saved == true) ref.invalidate(warehousesProvider);
}

class _WarehouseCard extends ConsumerWidget {
  const _WarehouseCard({required this.warehouse, required this.canAdmin});
  final Warehouse warehouse;
  final bool canAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final w = warehouse;
    final api = ref.read(apiProvider).inventory;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The title, chips and van wrap onto further lines on a narrow screen; the edit and
            // add-location actions keep their place at the end of the row.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Icon(
                        w.kind == 'van'
                            ? AppIcons.localShipping
                            : AppIcons.warehouse,
                      ),
                      Text(
                        '${w.code} · ${w.name}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Chip(
                        label: Text(
                          w.kind == 'van'
                              ? l.stockKindVan
                              : l.stockKindWarehouse,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                      if (!w.active)
                        Chip(
                          label: Text(l.inactive),
                          visualDensity: VisualDensity.compact,
                        ),
                      if (w.assignedUserName != null)
                        Text('${l.stockAssignedTo}: ${w.assignedUserName}'),
                    ],
                  ),
                ),
                if (canAdmin) ...[
                  IconButton(
                    tooltip: l.edit,
                    icon: const Icon(AppIcons.edit),
                    onPressed: () => _edit(context, ref, w, van: false),
                  ),
                  IconButton(
                    tooltip: l.stockNewLocation,
                    icon: const Icon(AppIcons.addLocationAlt),
                    onPressed: () async {
                      final code = await askText(
                        context,
                        title: l.stockNewLocation,
                        label: l.code,
                      );
                      if (code == null || code.isEmpty || !context.mounted) {
                        return;
                      }
                      if (await runAction(
                        context,
                        () => api.createLocation(
                          body: LocationInput(warehouseId: w.id, code: code),
                        ),
                      )) {
                        ref.invalidate(warehousesProvider);
                      }
                    },
                  ),
                ],
              ],
            ),
            for (final loc in w.locations)
              ListTile(
                dense: true,
                leading: const Icon(AppIcons.place),
                title: Text(
                  loc.name.isEmpty ? loc.code : '${loc.code} · ${loc.name}',
                ),
                trailing: canAdmin
                    ? Switch(
                        value: loc.active,
                        onChanged: (v) async {
                          if (await runAction(
                            context,
                            () => api.updateLocation(
                              id: loc.id,
                              body: LocationInput(
                                code: loc.code,
                                name: loc.name,
                                active: v,
                              ),
                            ),
                          )) {
                            ref.invalidate(warehousesProvider);
                          }
                        },
                      )
                    : (loc.active ? null : Text(l.inactive)),
              ),
          ],
        ),
      ),
    );
  }
}

class _WarehouseDialog extends ConsumerStatefulWidget {
  const _WarehouseDialog({this.warehouse, required this.van});
  final Warehouse? warehouse;
  final bool van;

  @override
  ConsumerState<_WarehouseDialog> createState() => _WarehouseDialogState();
}

class _WarehouseDialogState extends ConsumerState<_WarehouseDialog> {
  late final _code = TextEditingController(text: widget.warehouse?.code);
  late final _name = TextEditingController(text: widget.warehouse?.name);
  late String? _user = widget.warehouse?.assignedUserId;
  late bool _active = widget.warehouse?.active ?? true;
  List<CompanyUser> _users = [];
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.van) {
      ref
          .read(apiProvider)
          .core
          .listUsers()
          .then((u) {
            if (mounted) setState(() => _users = u);
          })
          .catchError((_) {});
    }
  }

  Future<void> _save() async {
    // A second tap while the first request is on its way must not create the warehouse twice.
    if (_saving) return;
    if (_code.text.trim().isEmpty || _name.text.trim().isEmpty) {
      setState(() => _error = context.l10n.codeNameRequired);
      return;
    }
    final body = WarehouseInput(
      code: _code.text.trim(),
      name: _name.text.trim(),
      kind: widget.van ? 'van' : 'warehouse',
      assignedUserId: widget.van ? _user : null,
      active: _active,
    );
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final api = ref.read(apiProvider).inventory;
      if (widget.warehouse == null) {
        await api.createWarehouse(body: body);
      } else {
        await api.updateWarehouse(id: widget.warehouse!.id, body: body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorMessage(e);
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(
        widget.warehouse != null
            ? widget.warehouse!.code
            : widget.van
            ? l.stockNewVan
            : l.stockNewWarehouse,
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _code,
              decoration: InputDecoration(labelText: l.code),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              decoration: InputDecoration(labelText: l.name),
            ),
            if (widget.van) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: _user,
                isExpanded: true,
                decoration: InputDecoration(labelText: l.stockAssignedTo),
                items: [
                  DropdownMenuItem<String?>(value: null, child: Text(l.none)),
                  // The assigned user stays selectable while the users load, or when the list
                  // does not contain them.
                  if (_user != null && !_users.any((u) => u.id == _user))
                    DropdownMenuItem<String?>(
                      value: _user,
                      child: Text(widget.warehouse?.assignedUserName ?? _user!),
                    ),
                  for (final u in _users)
                    DropdownMenuItem<String?>(
                      value: u.id,
                      child: Text(u.displayName),
                    ),
                ],
                onChanged: (v) => setState(() => _user = v),
              ),
            ],
            if (widget.warehouse != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l.active),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
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
          child: Text(l.cancel),
        ),
        TutorialTarget(
          id: 'warehouse-form-save',
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(l.save),
          ),
        ),
      ],
    );
  }
}
