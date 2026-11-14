import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/format.dart';
import 'job_extras.dart';
import '../../shared/app_icons.dart';

/// The installed units of a customer, their warranty and the jobs they were worked on in.
class CustomerEquipmentPage extends ConsumerStatefulWidget {
  const CustomerEquipmentPage({super.key, required this.customerId});
  final String customerId;

  @override
  ConsumerState<CustomerEquipmentPage> createState() =>
      _CustomerEquipmentPageState();
}

class _CustomerEquipmentPageState extends ConsumerState<CustomerEquipmentPage> {
  late Future<List<CustomerEquipment>> _units = _fetch();

  Future<List<CustomerEquipment>> _fetch() =>
      ref.read(apiProvider).field.listCustomerEquipment(id: widget.customerId);

  Future<void> _setWarranty(CustomerEquipment u) async {
    final l = context.l10n;
    var until = u.warrantyUntil;
    final note = TextEditingController(text: u.warrantyNote);
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, setLocal) => AlertDialog(
          title: Text(l.setWarranty),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton(
                onPressed: () async {
                  final p = await showDatePicker(
                    context: dialog,
                    initialDate: until ?? DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (p != null) setLocal(() => until = p);
                },
                child: Text(
                  '${l.warrantyUntilLabel}: ${until == null ? '—' : date(until)}',
                ),
              ),
              TextField(
                controller: note,
                decoration: InputDecoration(labelText: l.notes),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: Text(l.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(l.save),
            ),
          ],
        ),
      ),
    );
    final text = note.text.trim();
    note.dispose();
    if (saved != true || !mounted) return;
    try {
      await ref
          .read(apiProvider)
          .engineering
          .setWarranty(
            id: u.serialUnitId,
            body: WarrantyInput(warrantyUntil: until, warrantyNote: text),
          );
      if (mounted) setState(() => _units = _fetch());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(errorMessage(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final canWarranty =
        ref.watch(meProvider).value?.permissions.contains('serials.write') ??
        false;
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/jobs'),
        ),
        title: Text(l.customerEquipment),
      ),
      body: FutureBuilder<List<CustomerEquipment>>(
        future: _units,
        builder: (context, s) {
          if (s.hasError) return Center(child: Text(errorMessage(s.error!)));
          if (!s.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (s.data!.isEmpty) {
            return Center(child: Text(l.noCustomerEquipment));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final u in s.data!)
                Card(
                  child: ExpansionTile(
                    title: Text('${u.productCode} · ${u.productName}'),
                    subtitle: Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(u.serialNumber),
                        WarrantyChip(
                          status: u.warrantyStatus,
                          until: u.warrantyUntil,
                        ),
                        Text(l.jobCount('${u.jobs.length}')),
                      ],
                    ),
                    children: [
                      if (canWarranty)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            icon: const Icon(AppIcons.verified),
                            label: Text(l.setWarranty),
                            onPressed: () => _setWarranty(u),
                          ),
                        ),
                      for (final j in u.jobs)
                        ListTile(
                          dense: true,
                          title: Text('${j.number} · ${j.title}'),
                          subtitle: Text(
                            '${l.jobKind(j.kind)} · ${l.jobStatus(j.status)}'
                            '${j.completedAt == null ? '' : ' · ${date(j.completedAt!.toLocal())}'}',
                          ),
                          onTap: () => context.push('/jobs/${j.id}'),
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
