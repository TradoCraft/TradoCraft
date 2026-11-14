import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../api/generated/export.dart';
import '../l10n/l10n.dart';
import '../shared/photos.dart';
import 'portal_state.dart';
import '../shared/app_icons.dart';

final _when = DateFormat('dd/MM/yyyy');

Widget _repairChip(BuildContext context, String status) {
  final theme = Theme.of(context);
  return Chip(
    label: Text(context.l10n.portalRepairStatus(status)),
    backgroundColor: switch (status) {
      'waiting_customer' => theme.colorScheme.tertiaryContainer,
      'ready' => theme.colorScheme.primaryContainer,
      _ => null,
    },
    visualDensity: VisualDensity.compact,
  );
}

/// The customer's repairs and their simplified status.
class PortalRepairsPage extends ConsumerWidget {
  const PortalRepairsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final repairs = ref.watch(portalRepairsProvider);
    final me = ref.watch(portalProfileProvider).value;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/repairs/new'),
        icon: const Icon(AppIcons.add),
        label: Text(l.announceRepair),
      ),
      body: repairs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(portalError(e))),
        data: (list) => list.isEmpty
            ? Center(child: Text(l.noRepairsYet))
            : RefreshIndicator(
                onRefresh: () async =>
                    ref.refresh(portalRepairsProvider.future),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                  children: [
                    Text(
                      l.myRepairs,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    for (final r in list)
                      Card(
                        child: ListTile(
                          onTap: () => context.go('/repairs/${r.id}'),
                          title: Text(
                            '${r.number}  ${[r.productDescription, r.serialNumber].where((e) => e.isNotEmpty).join(' · ')}',
                          ),
                          subtitle: Text(
                            [
                              r.faultDescription,
                              if (me != null &&
                                  r.contactName.isNotEmpty &&
                                  r.contactName != me.fullName)
                                l.raisedBy(r.contactName),
                              _when.format(r.updatedAt.toLocal()),
                            ].join('  ·  '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: _repairChip(context, r.status),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// One repair: its status and the photos, with the possibility to add more until it is finished.
class PortalRepairPage extends ConsumerWidget {
  const PortalRepairPage({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final detail = ref.watch(portalRepairProvider(id));
    return detail.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(portalError(e))),
      data: (d) {
        final r = d.repair;
        final finished = r.status == 'shipped' || r.status == 'cancelled';
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: () => context.go('/repairs'),
                  icon: const Icon(AppIcons.arrowBack),
                ),
                Expanded(
                  child: Text(r.number, style: theme.textTheme.titleLarge),
                ),
                _repairChip(context, r.status),
              ],
            ),
            if (r.status == 'announced')
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(l.repairAnnouncedOk),
              ),
            const SizedBox(height: 8),
            Text(l.productDescription, style: theme.textTheme.labelMedium),
            Text(
              [
                r.productDescription,
                r.serialNumber,
              ].where((e) => e.isNotEmpty).join(' · '),
            ),
            const SizedBox(height: 8),
            Text(l.faultDescription, style: theme.textTheme.labelMedium),
            SelectableText(r.faultDescription),
            if (r.customerReference.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(l.customerReference, style: theme.textTheme.labelMedium),
              Text(r.customerReference),
            ],
            const Divider(height: 32),
            PhotoGallery(
              photos: [
                for (final p in d.photos)
                  PhotoItem(id: p.id, caption: p.caption, by: p.uploaderName),
              ],
              dio: ref.watch(portalDioProvider),
              pathFor: (photo) => '/api/v1/portal/repairs/$id/photos/$photo',
              onAdd: finished
                  ? null
                  : (photos) async {
                      final dio = ref.read(portalDioProvider);
                      for (final p in photos) {
                        await uploadPhoto(
                          dio,
                          '/api/v1/portal/repairs/$id/photos',
                          p,
                        );
                      }
                      ref.invalidate(portalRepairProvider(id));
                      ref.invalidate(portalRepairsProvider);
                    },
            ),
          ],
        );
      },
    );
  }
}

/// Announces a repair, with photos chosen up front. The repair is created first and the photos
/// follow; if a photo fails the repair still exists and photos can be added from its page.
class PortalAnnounceRepairPage extends ConsumerStatefulWidget {
  const PortalAnnounceRepairPage({super.key, this.pick = pickPhotos});

  /// Chooses pictures (replaced in tests).
  final PhotoPicker pick;

  @override
  ConsumerState<PortalAnnounceRepairPage> createState() =>
      _PortalAnnounceRepairPageState();
}

class _PortalAnnounceRepairPageState
    extends ConsumerState<PortalAnnounceRepairPage> {
  final _product = TextEditingController();
  final _serial = TextEditingController();
  final _fault = TextEditingController();
  final _reference = TextEditingController();
  final _photos = <PickedPhoto>[];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final t in [_product, _serial, _fault, _reference]) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> _send() async {
    final l = context.l10n;
    if (_fault.text.trim().isEmpty ||
        (_product.text.trim().isEmpty && _serial.text.trim().isEmpty)) {
      setState(() => _error = l.required);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = ref.read(portalApiProvider);
    try {
      final d = await api.announcePortalRepair(
        body: AnnounceRepair(
          productDescription: _product.text.trim(),
          serialNumber: _serial.text.trim(),
          faultDescription: _fault.text.trim(),
          customerReference: _reference.text.trim(),
        ),
      );
      ref.invalidate(portalRepairsProvider);
      String? photoError;
      final dio = ref.read(portalDioProvider);
      for (final p in _photos) {
        try {
          await uploadPhoto(
            dio,
            '/api/v1/portal/repairs/${d.repair.id}/photos',
            p,
          );
        } catch (e) {
          photoError = portalError(e);
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(photoError ?? l.repairAnnouncedOk)),
      );
      context.go('/repairs/${d.repair.id}');
    } catch (e) {
      if (mounted) setState(() => _error = portalError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    const gap = SizedBox(height: 12);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            IconButton(
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: () => context.go('/repairs'),
              icon: const Icon(AppIcons.arrowBack),
            ),
            Text(
              l.announceRepair,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
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
          minLines: 4,
          maxLines: 10,
          decoration: InputDecoration(labelText: l.faultDescription),
        ),
        gap,
        TextField(
          controller: _reference,
          decoration: InputDecoration(labelText: l.yourReference),
        ),
        gap,
        Text(l.repairPhotosHelp),
        Row(
          children: [
            TextButton.icon(
              onPressed: _busy
                  ? null
                  : () async {
                      final picked = await widget.pick(context);
                      if (mounted) setState(() => _photos.addAll(picked));
                    },
              icon: const Icon(AppIcons.addAPhoto),
              label: Text(l.addPhoto),
            ),
            if (_photos.isNotEmpty) Text('${l.photos} (${_photos.length})'),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        gap,
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: _busy ? null : _send,
            child: Text(l.announceRepair),
          ),
        ),
      ],
    );
  }
}
