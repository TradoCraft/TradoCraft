import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../shared/power_text.dart';
import '../../l10n/l10n.dart';
import '../../shared/app_icons.dart';

/// Lists the power grid reference data by country and lets product managers add and edit grids.
class PowerGridsDialog extends ConsumerStatefulWidget {
  const PowerGridsDialog({super.key});

  @override
  ConsumerState<PowerGridsDialog> createState() => _PowerGridsDialogState();
}

class _PowerGridsDialogState extends ConsumerState<PowerGridsDialog> {
  final _filter = TextEditingController();

  /// The country filter in use: empty (all) or a complete two-letter code.
  String get _country {
    final c = _filter.text.trim().toUpperCase();
    return c.length == 2 ? c : '';
  }

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  Future<void> _edit([PowerGrid? g]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _GridEditor(grid: g),
    );
    if (saved == true) ref.invalidate(powerGridsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final grids = ref.watch(powerGridsProvider(_country));
    final canWrite = can(ref, 'products.write');
    return AlertDialog(
      title: Text(l.powerGridsTitle),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 160,
              child: TextField(
                key: const ValueKey('grid-filter'),
                controller: _filter,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(2),
                  TextInputFormatter.withFunction(
                    (old, v) => v.copyWith(text: v.text.toUpperCase()),
                  ),
                ],
                decoration: InputDecoration(
                  labelText: l.country,
                  prefixIcon: const Icon(AppIcons.search),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: grids.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text(errorMessage(e)),
                data: (list) => ListView.builder(
                  shrinkWrap: true,
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final g = list[i];
                    return ListTile(
                      key: ValueKey('grid-${g.id}'),
                      title: Text(
                        '${g.countryCode} · ${powerProfileText(voltage: g.voltageV, phases: g.phases, frequency: g.frequencyHz)}',
                      ),
                      subtitle: Text(
                        [
                          g.name,
                          g.active ? l.active : l.inactive,
                        ].where((s) => s.isNotEmpty).join(' · '),
                      ),
                      trailing: canWrite
                          ? IconButton(
                              tooltip: context.l10n.edit,
                              icon: const Icon(AppIcons.edit),
                              onPressed: () => _edit(g),
                            )
                          : null,
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (canWrite)
          TextButton.icon(
            onPressed: _edit,
            icon: const Icon(AppIcons.add),
            label: Text(l.newPowerGrid),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.close),
        ),
      ],
    );
  }
}

class _GridEditor extends ConsumerStatefulWidget {
  const _GridEditor({this.grid});
  final PowerGrid? grid;

  @override
  ConsumerState<_GridEditor> createState() => _GridEditorState();
}

class _GridEditorState extends ConsumerState<_GridEditor> {
  late final _country = TextEditingController(text: widget.grid?.countryCode);
  late final _voltage = TextEditingController(
    text: widget.grid == null ? '' : '${widget.grid!.voltageV}',
  );
  late final _name = TextEditingController(text: widget.grid?.name);
  late int _phases = widget.grid?.phases ?? 1;
  late int _frequency = widget.grid?.frequencyHz ?? 50;
  late bool _active = widget.grid?.active ?? true;
  String? _error;

  @override
  void dispose() {
    _country.dispose();
    _voltage.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final country = _country.text.trim().toUpperCase();
    final voltage = int.tryParse(_voltage.text.trim());
    if (country.length != 2 || voltage == null || voltage <= 0) {
      setState(() => _error = context.l10n.powerGridInvalid);
      return;
    }
    final body = PowerGridInput(
      countryCode: country,
      voltageV: voltage,
      phases: _phases,
      frequencyHz: _frequency,
      name: _name.text.trim().isEmpty ? null : _name.text.trim(),
      active: _active,
    );
    final api = ref.read(apiProvider).products;
    try {
      if (widget.grid == null) {
        await api.createPowerGrid(body: body);
      } else {
        await api.updatePowerGrid(id: widget.grid!.id, body: body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(widget.grid == null ? l.newPowerGrid : l.powerGrid),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const ValueKey('grid-country'),
                controller: _country,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(2),
                  TextInputFormatter.withFunction(
                    (old, v) => v.copyWith(text: v.text.toUpperCase()),
                  ),
                ],
                decoration: InputDecoration(labelText: l.country),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('grid-voltage'),
                controller: _voltage,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(labelText: l.voltageV),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                key: const ValueKey('grid-phases'),
                initialValue: _phases,
                decoration: InputDecoration(labelText: l.phases),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('1')),
                  DropdownMenuItem(value: 3, child: Text('3')),
                ],
                onChanged: (v) => setState(() => _phases = v!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                key: const ValueKey('grid-frequency'),
                initialValue: _frequency,
                decoration: InputDecoration(labelText: l.frequencyHz),
                items: const [
                  DropdownMenuItem(value: 50, child: Text('50')),
                  DropdownMenuItem(value: 60, child: Text('60')),
                ],
                onChanged: (v) => setState(() => _frequency = v!),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('grid-name'),
                controller: _name,
                decoration: InputDecoration(labelText: l.name),
              ),
              SwitchListTile(
                key: const ValueKey('grid-active'),
                contentPadding: EdgeInsets.zero,
                title: Text(l.active),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
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
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(onPressed: _save, child: Text(l.save)),
      ],
    );
  }
}
