import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/actions.dart';
import '../../shared/app_icons.dart';
import '../../shared/photos.dart' show newClientId;
import '../../shared/search_picker.dart';
import 'link_flow.dart';

/// Suggestions for an opened repair parcel: announced repairs ranked by how well they fit, each
/// with its reasons and a button that starts the explicit confirm step. Or create a new repair.
/// Pops true when something was linked.
class LinkParcelDialog extends ConsumerStatefulWidget {
  const LinkParcelDialog({super.key, required this.pkg});
  final Package pkg;

  @override
  ConsumerState<LinkParcelDialog> createState() => _LinkParcelDialogState();
}

class _LinkParcelDialogState extends ConsumerState<LinkParcelDialog> {
  final _serial = TextEditingController();
  final _ticket = TextEditingController();
  final _product = TextEditingController();
  PackageRepairSuggestions? _result;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_serial, _ticket, _product]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    String? v(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    try {
      final r = await ref
          .read(apiProvider)
          .repairs
          .listPackageRepairSuggestions(
            id: widget.pkg.id,
            serial: v(_serial),
            ticket: v(_ticket),
            product: v(_product),
          );
      if (mounted) setState(() => _result = r);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirm(Repair repair) async {
    final linked = await confirmAndLink(
      context,
      ref,
      pkg: widget.pkg,
      repair: repair,
    );
    if (!mounted) return;
    if (linked) {
      Navigator.pop(context, true);
    } else {
      // Maybe someone else got there first: show what is true now.
      await _load();
    }
  }

  Future<void> _createNew() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => NewRepairFromParcelDialog(pkg: widget.pkg),
    );
    if (created == true && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final items = _result?.suggestions ?? const <RepairSuggestion>[];
    return AlertDialog(
      title: Text('${l.linkToRepair} · ${widget.pkg.number}'),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _serial,
                      decoration: InputDecoration(labelText: l.serialNumber),
                      onSubmitted: (_) => _load(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _ticket,
                      decoration: InputDecoration(labelText: l.ticket),
                      onSubmitted: (_) => _load(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _product,
                      decoration: InputDecoration(
                        labelText: l.productDescription,
                      ),
                      onSubmitted: (_) => _load(),
                    ),
                  ),
                  IconButton(
                    tooltip: l.search,
                    icon: const Icon(AppIcons.search),
                    onPressed: _load,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(l.repairSuggestions, style: theme.textTheme.titleSmall),
              if (_result?.proposedCustomerName != null)
                Text(l.suggestedCustomer(_result!.proposedCustomerName!)),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                Text(_error!, style: TextStyle(color: theme.colorScheme.error))
              else if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(l.noSuggestions),
                ),
              for (final s in items)
                Card(
                  key: ValueKey('suggestion-${s.repair.id}'),
                  child: ListTile(
                    title: Text(
                      '${s.repair.number} · ${s.repair.customerName}',
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          [
                            s.repair.productDescription,
                            s.repair.serialNumber,
                          ].where((e) => e.isNotEmpty).join(' · '),
                        ),
                        Wrap(
                          spacing: 6,
                          children: [
                            for (final r in s.reasons)
                              Chip(
                                label: Text(l.reasonLabel(r)),
                                visualDensity: VisualDensity.compact,
                              ),
                            Chip(
                              label: Text(l.suggestionScore('${s.score}')),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                      ],
                    ),
                    trailing: FilledButton(
                      key: ValueKey('link-${s.repair.id}'),
                      onPressed: () => _confirm(s.repair),
                      child: Text(l.linkToRepair),
                    ),
                  ),
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
        OutlinedButton.icon(
          icon: const Icon(AppIcons.addCircle),
          label: Text(l.createNewRepair),
          onPressed: _createNew,
        ),
      ],
    );
  }
}

/// Creates a repair straight from the parcel (nothing announced matches).
class NewRepairFromParcelDialog extends ConsumerStatefulWidget {
  const NewRepairFromParcelDialog({super.key, required this.pkg});
  final Package pkg;

  @override
  ConsumerState<NewRepairFromParcelDialog> createState() =>
      _NewRepairFromParcelDialogState();
}

class _NewRepairFromParcelDialogState
    extends ConsumerState<NewRepairFromParcelDialog> {
  final _product = TextEditingController();
  final _serial = TextEditingController();
  final _fault = TextEditingController();
  late final _reference = TextEditingController(
    text: widget.pkg.customerReference,
  );
  late String? _customerId = widget.pkg.customerId;
  late String? _customerName = widget.pkg.customerName;
  final _clientId = newClientId();
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_product, _serial, _fault, _reference]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Creating a repair for another customer than the parcel's is allowed, but asked about first.
  Future<bool> _confirmOtherCustomer() async {
    final l = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        content: Text(
          '${l.customerMismatchWarning}\n'
          '${widget.pkg.customerName} / $_customerName',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.createNewRepair),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _save() async {
    final other =
        widget.pkg.customerId != null && _customerId != widget.pkg.customerId;
    if (other && !await _confirmOtherCustomer()) return;
    if (!mounted) return;
    setState(() => _busy = true);
    final ok = await runAction(context, () async {
      await ref
          .read(apiProvider)
          .repairs
          .linkPackageRepair(
            id: widget.pkg.id,
            body: PackageRepairLinkInput(
              clientId: _clientId,
              confirmCustomerMismatch: other ? true : null,
              newRepair: PackageNewRepairInput(
                customerId: _customerId,
                productDescription: _product.text.trim(),
                serialNumber: _serial.text.trim(),
                faultDescription: _fault.text.trim().isEmpty
                    ? null
                    : _fault.text.trim(),
                customerReference: _reference.text.trim(),
              ),
            ),
          );
    }, success: context.l10n.parcelLinked);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    const gap = SizedBox(height: 12);
    return AlertDialog(
      title: Text(l.createNewRepair),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_customerName != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _customerName!,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              SearchPicker<Customer>(
                label: l.customer,
                display: (c) => '${c.code} · ${c.name}',
                search: (q) async =>
                    (await ref
                            .read(apiProvider)
                            .crm
                            .listCustomers(q: q, limit: 20))
                        .items,
                onSelected: (c) => setState(() {
                  _customerId = c.id;
                  _customerName = c.name;
                }),
              ),
              gap,
              TextField(
                controller: _product,
                decoration: InputDecoration(labelText: l.productDescription),
              ),
              gap,
              TextField(
                controller: _serial,
                decoration: InputDecoration(labelText: l.serialNumber),
              ),
              gap,
              TextField(
                controller: _fault,
                minLines: 2,
                maxLines: 6,
                decoration: InputDecoration(labelText: l.faultDescription),
              ),
              gap,
              TextField(
                controller: _reference,
                decoration: InputDecoration(labelText: l.customerReference),
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
        FilledButton(
          onPressed: _busy || _customerId == null ? null : _save,
          child: Text(l.createNewRepair),
        ),
      ],
    );
  }
}
