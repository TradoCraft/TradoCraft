import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/actions.dart';
import '../../shared/app_icons.dart';
import '../../shared/format.dart';
import '../../shared/photos.dart';
import '../../shared/search_picker.dart';

const _carriers = ['PostNL', 'bpost', 'DHL', 'UPS', 'FedEx', 'GLS', 'DPD'];
const packageConditions = ['intact', 'damaged', 'opened', 'wet'];

/// Goods in: a quick form to register a parcel that arrives at the dock, and the parcels that are
/// registered and still waiting. The tracking field is focused so a scanner can fill it.
class ReceivingPage extends ConsumerStatefulWidget {
  const ReceivingPage({super.key, this.pick = pickPhotos});

  /// Chooses the pictures of the box (replaceable in tests).
  final PhotoPicker pick;

  @override
  ConsumerState<ReceivingPage> createState() => _ReceivingPageState();
}

class _ReceivingPageState extends ConsumerState<ReceivingPage> {
  final _sender = TextEditingController();
  final _carrier = TextEditingController();
  final _tracking = TextEditingController();
  final _count = TextEditingController(text: '1');
  final _conditionNote = TextEditingController();
  final _reference = TextEditingController();
  final _trackingFocus = FocusNode();
  Customer? _customer;
  String _condition = 'intact';
  final _photos = <_Photo>[];
  // Kept until the parcel is saved, so a retry after a bad connection registers it only once.
  String _clientId = newClientId();
  int _formKey = 0;
  bool _busy = false;
  Future<PackagePage>? _list;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    for (final c in [
      _sender,
      _carrier,
      _tracking,
      _count,
      _conditionNote,
      _reference,
    ]) {
      c.dispose();
    }
    _trackingFocus.dispose();
    super.dispose();
  }

  void _reload() {
    _list = ref
        .read(apiProvider)
        .repairs
        .listPackages(status: 'open', limit: 50);
  }

  Future<void> _addPhotos() async {
    final picked = await widget.pick(context);
    // The list is frozen while a save is under way (the picker may have been open before it).
    if (picked.isEmpty || !mounted || _busy) return;
    setState(() => _photos.addAll(picked.map(_Photo.new)));
  }

  /// The registered parcel as the form describes it, keeping the notes the server holds.
  PackageInput _input(String notes) => PackageInput(
    clientId: _clientId,
    customerId: _customer?.id,
    senderName: _sender.text.trim(),
    carrier: _carrier.text.trim(),
    trackingNumber: _tracking.text.trim(),
    parcelCount: int.tryParse(_count.text.trim()) ?? 1,
    condition: _condition,
    conditionNote: _conditionNote.text.trim(),
    customerReference: _reference.text.trim(),
    notes: notes,
  );

  /// A retry with the same client id returns the parcel as first registered: when the operator
  /// has corrected details since, bring that parcel up to date.
  Future<PackageDetail> _reconcile(
    RepairsClient api,
    PackageDetail created,
    PackageInput wanted,
  ) async {
    final p = created.package;
    final same =
        p.customerId == wanted.customerId &&
        p.senderName == wanted.senderName &&
        p.carrier == wanted.carrier &&
        p.trackingNumber == wanted.trackingNumber &&
        p.parcelCount == wanted.parcelCount &&
        p.condition == wanted.condition &&
        p.conditionNote == wanted.conditionNote &&
        p.customerReference == wanted.customerReference;
    if (same) return created;
    return api.updatePackage(id: p.id, body: wanted);
  }

  Future<void> _close(Package p) async {
    final l = context.l10n;
    final note = await askText(
      context,
      title: '${l.closeParcel} · ${p.number}',
      label: l.notes,
    );
    if (note == null || !mounted) return;
    if (note.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.noteRequired)));
      return;
    }
    await runAction(
      context,
      () => ref
          .read(apiProvider)
          .repairs
          .closePackage(
            id: p.id,
            body: PackageCloseInput(note: note),
          ),
    );
    if (mounted) setState(_reload);
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final l = context.l10n;
    final dio = ref.read(dioProvider);
    final api = ref.read(apiProvider);
    PackageDetail? saved;
    final photos = List<_Photo>.of(_photos);
    final ok = await runAction(context, () async {
      final created = await api.repairs.createPackage(body: _input(''));
      final reconciled = await _reconcile(
        api.repairs,
        created,
        _input(created.package.notes),
      );
      for (final p in photos) {
        await uploadPhoto(
          dio,
          '/api/v1/packages/${reconciled.package.id}/photos',
          p.photo,
          clientId: p.clientId,
        );
      }
      saved = reconciled;
    }, success: null);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok || saved == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.parcelRegistered(saved!.package.number))),
    );
    // Back to an empty form for the next parcel.
    setState(() {
      for (final c in [
        _sender,
        _carrier,
        _tracking,
        _conditionNote,
        _reference,
      ]) {
        c.clear();
      }
      _count.text = '1';
      _customer = null;
      _condition = 'intact';
      _photos.clear();
      _clientId = newClientId();
      _formKey++;
      _reload();
    });
    _trackingFocus.requestFocus();
  }

  Widget _form(BuildContext context) {
    final l = context.l10n;
    const gap = SizedBox(height: 12, width: 12);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.registerParcel,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            gap,
            TextField(
              controller: _tracking,
              focusNode: _trackingFocus,
              autofocus: true,
              decoration: InputDecoration(labelText: l.trackingNumber),
            ),
            gap,
            SearchPicker<Customer>(
              key: ValueKey('customer-$_formKey'),
              label: l.customerOptional,
              display: (c) => '${c.code} · ${c.name}',
              search: (q) async =>
                  (await ref
                          .read(apiProvider)
                          .crm
                          .listCustomers(q: q, limit: 20))
                      .items,
              onSelected: (c) => _customer = c,
            ),
            gap,
            TextField(
              controller: _sender,
              decoration: InputDecoration(labelText: l.sender),
            ),
            gap,
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _carrier,
                    decoration: InputDecoration(labelText: l.carrier),
                  ),
                ),
                gap,
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _count,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: l.parcelCount),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              children: [
                for (final c in _carriers)
                  ActionChip(
                    label: Text(c),
                    onPressed: () => setState(() => _carrier.text = c),
                  ),
              ],
            ),
            gap,
            Text(
              l.packageCondition,
              style: Theme.of(context).textTheme.labelMedium,
            ),
            Wrap(
              spacing: 6,
              children: [
                for (final c in packageConditions)
                  ChoiceChip(
                    key: ValueKey('condition-$c'),
                    label: Text(l.packageConditionLabel(c)),
                    selected: _condition == c,
                    onSelected: (_) => setState(() => _condition = c),
                  ),
              ],
            ),
            if (_condition != 'intact') ...[
              gap,
              TextField(
                controller: _conditionNote,
                decoration: InputDecoration(labelText: l.conditionNote),
              ),
            ],
            gap,
            TextField(
              controller: _reference,
              decoration: InputDecoration(labelText: l.customerReference),
            ),
            gap,
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : _addPhotos,
                  icon: const Icon(AppIcons.addAPhoto),
                  label: Text(l.addPhoto),
                ),
                for (var i = 0; i < _photos.length; i++)
                  InputChip(
                    label: Text(_photos[i].photo.filename),
                    deleteIcon: const Icon(AppIcons.close, size: 16),
                    deleteButtonTooltipMessage: l.removePhoto,
                    onDeleted: _busy
                        ? null
                        : () => setState(() => _photos.removeAt(i)),
                  ),
              ],
            ),
            gap,
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _busy ? null : _save,
                icon: const Icon(AppIcons.moveToInbox),
                label: Text(l.registerParcel),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list_(BuildContext context) {
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l.registeredParcels,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Spacer(),
            IconButton(
              tooltip: l.offlineReload,
              icon: const Icon(AppIcons.refresh),
              onPressed: () => setState(_reload),
            ),
          ],
        ),
        FutureBuilder<PackagePage>(
          future: _list,
          builder: (context, s) {
            if (s.hasError) return Text(errorMessage(s.error!));
            if (!s.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final items = s.data!.items;
            if (items.isEmpty) return Text(l.noParcels);
            final canClose =
                can(ref, 'packages.write') && !can(ref, 'repairs.intake');
            return Column(
              children: [
                for (final p in items)
                  PackageTile(
                    package: p,
                    trailing: canClose && p.status == 'registered'
                        ? OutlinedButton(
                            onPressed: () => _close(p),
                            child: Text(l.closeParcel),
                          )
                        : null,
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final canWrite = can(ref, 'packages.write');
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final form = canWrite ? _form(context) : null;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.packagesReceiving)),
      body: wide && form != null
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 460,
                    child: SingleChildScrollView(child: form),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: SingleChildScrollView(child: _list_(context)),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [?form, const SizedBox(height: 16), _list_(context)],
            ),
    );
  }
}

/// A chosen picture with its own client id, kept across retries so it is stored only once.
class _Photo {
  _Photo(this.photo) : clientId = newClientId();
  final PickedPhoto photo;
  final String clientId;
}

/// One parcel in a list: number, sender and customer, carrier, tracking, state.
class PackageTile extends StatelessWidget {
  const PackageTile({super.key, required this.package, this.trailing});
  final Package package;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final p = package;
    return ListTile(
      leading: const Icon(AppIcons.inventory2),
      title: Text(
        [
          p.number,
          if (p.senderName.isNotEmpty) p.senderName,
          p.customerName ?? l.customerUnknown,
        ].join(' · '),
      ),
      subtitle: Text(
        [
          if (p.carrier.isNotEmpty) p.carrier,
          if (p.trackingNumber.isNotEmpty) p.trackingNumber,
          '${p.parcelCount}×',
          l.packageConditionLabel(p.condition),
          l.packageStatus(p.status),
          if (p.kind != null) l.packageKind(p.kind!),
          date(p.receivedAt.toLocal()),
        ].join(' · '),
      ),
      trailing: trailing,
    );
  }
}
