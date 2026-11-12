import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/actions.dart';
import '../../shared/app_icons.dart';
import '../../shared/format.dart';
import '../tutorial/targets.dart';

/// Lines of confirmed orders that are built from a BOM and not yet covered by production orders:
/// what the planner can release, most urgent orders first.
class ReleasePage extends ConsumerStatefulWidget {
  const ReleasePage({super.key});

  @override
  ConsumerState<ReleasePage> createState() => _ReleasePageState();
}

class _ReleasePageState extends ConsumerState<ReleasePage> {
  List<ProductionToRelease>? _items;
  String? _error;
  String? _busy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await ref.read(apiProvider).production.toRelease();
      if (mounted) {
        setState(() {
          _items = items;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  Future<void> _release(ProductionToRelease t) async {
    setState(() => _busy = t.orderLineId);
    final l = context.l10n;
    String? opened;
    final ok = await runAction(context, () async {
      final po = await ref
          .read(apiProvider)
          .production
          .release(
            body: ReleaseProductionInput(
              orderId: t.orderId,
              orderLineId: t.orderLineId,
            ),
          );
      opened = po.id;
    }, success: l.productionReleased);
    if (mounted) setState(() => _busy = null);
    if (ok && opened != null && mounted) {
      await context.push('/production/$opened');
    }
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final canRelease =
        ref.watch(meProvider).value?.permissions.contains('production.write') ??
        false;
    final items = _items;
    return Scaffold(
      appBar: AppBar(title: Text(l.productionToRelease)),
      body: _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!),
                  TextButton(onPressed: _load, child: Text(l.retry)),
                ],
              ),
            )
          : items == null
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
          ? Center(child: Text(l.productionNothingToRelease))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final t in items)
                  Card(
                    key: ValueKey('release-${t.orderLineId}'),
                    child: ListTile(
                      title: Text(
                        '${t.productCode} · ${t.productName} · ${number(t.toBuild)}',
                      ),
                      subtitle: Text(
                        '${t.orderNumber} · ${t.customerName} · ${l.orderPriority(t.priority)}',
                      ),
                      trailing: canRelease
                          ? TutorialTarget(id: 'production-release-line', child: FilledButton.icon(
                              key: ValueKey('release-button-${t.orderLineId}'),
                              icon: const Icon(AppIcons.outbox),
                              label: Text(l.productionRelease),
                              onPressed: _busy == null
                                  ? () => _release(t)
                                  : null,
                            ))
                          : null,
                      onTap: () => context.push('/orders/${t.orderId}'),
                    ),
                  ),
              ],
            ),
    );
  }
}
