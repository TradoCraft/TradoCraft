import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/actions.dart';
import '../../shared/app_icons.dart';
import 'link_flow.dart';

/// The parcels a repair arrived in, with unlink (for a mistake), and, for an announced repair,
/// the opened parcels of the same customer that may be this one. Linking asks for confirmation.
class RepairPackagesSection extends ConsumerStatefulWidget {
  const RepairPackagesSection({
    super.key,
    required this.repair,
    this.onChanged,
  });
  final Repair repair;

  /// Called after a parcel was linked or unlinked, so the repair can be reloaded.
  final VoidCallback? onChanged;

  @override
  ConsumerState<RepairPackagesSection> createState() =>
      _RepairPackagesSectionState();
}

class _RepairPackagesSectionState extends ConsumerState<RepairPackagesSection> {
  List<Package>? _linked;
  List<Package> _suggestions = const [];
  String? _error;

  RepairsClient get _api => ref.read(apiProvider).repairs;
  bool get _canIntake => can(ref, 'repairs.intake');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final linked = await _api.listRepairPackages(id: widget.repair.id);
      var suggestions = <Package>[];
      if (_canIntake &&
          (widget.repair.status == 'announced' ||
              widget.repair.status == 'received')) {
        suggestions = await _api.listRepairPackageSuggestions(
          id: widget.repair.id,
        );
      }
      if (mounted) {
        setState(() {
          _linked = linked;
          _suggestions = suggestions;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  Future<void> _link(Package p) async {
    await confirmAndLink(context, ref, pkg: p, repair: widget.repair);
    await _load();
    widget.onChanged?.call();
  }

  Future<void> _unlink(Package p) async {
    final ok = await runAction(
      context,
      () => _api.unlinkPackageRepair(id: p.id, repairId: widget.repair.id),
      success: context.l10n.parcelUnlinked,
    );
    await _load();
    if (ok) widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final linked = _linked;
    String describe(Package p) => [
      p.number,
      if (p.senderName.isNotEmpty) p.senderName,
      if (p.carrier.isNotEmpty) p.carrier,
      if (p.trackingNumber.isNotEmpty) p.trackingNumber,
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.parcelsSection, style: theme.textTheme.titleSmall),
        if (_error != null)
          Text(_error!, style: TextStyle(color: theme.colorScheme.error))
        else if (linked == null)
          const LinearProgressIndicator()
        else if (linked.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(l.noParcelsLinked, style: theme.textTheme.bodySmall),
          ),
        for (final p in linked ?? const <Package>[])
          ListTile(
            key: ValueKey('linked-${p.id}'),
            dense: true,
            leading: const Icon(AppIcons.inventory2),
            title: Text(describe(p)),
            trailing: _canIntake
                ? IconButton(
                    tooltip: l.unlinkParcel,
                    icon: const Icon(AppIcons.linkOff),
                    onPressed: () => _unlink(p),
                  )
                : null,
          ),
        if (_suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(l.parcelsToLink, style: theme.textTheme.labelMedium),
          for (final p in _suggestions)
            ListTile(
              key: ValueKey('suggested-${p.id}'),
              dense: true,
              leading: const Icon(AppIcons.lightbulb),
              title: Text(describe(p)),
              trailing: FilledButton(
                onPressed: () => _link(p),
                child: Text(l.linkParcel),
              ),
            ),
        ],
      ],
    );
  }
}
