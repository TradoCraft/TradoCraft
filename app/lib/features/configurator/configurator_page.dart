import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/actions.dart';
import '../../shared/app_icons.dart';
import '../../shared/format.dart';
import '../../shared/search_picker.dart';

final configuratorModelsProvider =
    FutureProvider.autoDispose<List<ModelSummary>>(
      (ref) async => (await ref.watch(apiProvider).configurator.listModels())
          .where((m) => m.active && m.activeRevisionId != null)
          .toList(),
    );

final savedConfigurationsProvider =
    FutureProvider.autoDispose<List<ConfigurationSummary>>(
      (ref) => ref.watch(apiProvider).configurator.listConfigurations(),
    );

/// The configurators the user can run and the saved configurations. [customerId] (from a
/// customer or quotation) preselects the customer of a new configuration.
class ConfiguratorPage extends ConsumerWidget {
  const ConfiguratorPage({super.key, this.customerId});

  final String? customerId;

  Future<void> _start(
    BuildContext context,
    WidgetRef ref,
    ModelSummary m,
  ) async {
    final created = await showDialog<Configuration>(
      context: context,
      builder: (_) => NewConfigurationDialog(model: m, customerId: customerId),
    );
    if (created == null || !context.mounted) return;
    await context.push('/configurator/configurations/${created.id}');
    ref.invalidate(savedConfigurationsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final models = ref.watch(configuratorModelsProvider);
    final saved = ref.watch(savedConfigurationsProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(configuratorModelsProvider);
        ref.invalidate(savedConfigurationsProvider);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.configurator,
                  style: theme.textTheme.headlineSmall,
                ),
              ),
              if (can(ref, 'configurator.design'))
                OutlinedButton.icon(
                  key: const ValueKey('design-configurators'),
                  onPressed: () async {
                    await context.push('/configurator/builder');
                    ref.invalidate(configuratorModelsProvider);
                  },
                  icon: const Icon(AppIcons.edit),
                  label: Text(l10n.cfgbDesignTitle),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(l10n.configurators, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          models.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text(errorMessage(e)),
            data: (list) => list.isEmpty
                ? Text(l10n.cfgNoModels)
                : Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final m in list)
                        SizedBox(
                          width: 320,
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    m.name,
                                    style: theme.textTheme.titleMedium,
                                  ),
                                  Text(
                                    '${m.code} · ${l10n.cfgRevision(m.activeRevision ?? 0)}',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                  if (m.description.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      m.description,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: FilledButton.icon(
                                      onPressed: () => _start(context, ref, m),
                                      icon: const Icon(AppIcons.add),
                                      label: Text(l10n.newConfiguration),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 24),
          Text(l10n.savedConfigurations, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          saved.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text(errorMessage(e)),
            data: (list) => list.isEmpty
                ? Text(l10n.cfgNoConfigurations)
                : Card(
                    child: Column(
                      children: [
                        for (final c in list)
                          ListTile(
                            key: ValueKey('cfg-${c.id}'),
                            leading: Icon(
                              c.quotationId == null
                                  ? AppIcons.dashboardCustomize
                                  : AppIcons.requestQuote,
                            ),
                            title: Text(
                              c.name.isEmpty
                                  ? c.modelName
                                  : '${c.name} · ${c.modelName}',
                            ),
                            subtitle: Text(
                              [
                                c.customerName ?? l10n.cfgNoCustomer,
                                l10n.cfgRevision(c.revision),
                                if (c.newerRevision != null)
                                  l10n.cfgNewerRevisionAvailable(
                                    c.newerRevision!,
                                  ),
                                ?c.quotationNumber,
                                date(c.updatedAt.toLocal()),
                              ].join(' · '),
                            ),
                            trailing: IconButton(
                              tooltip: l10n.remove,
                              icon: const Icon(AppIcons.delete),
                              onPressed: () async {
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    content: Text(l10n.cfgDeleteConfirm),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: Text(l10n.cancel),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: Text(l10n.remove),
                                      ),
                                    ],
                                  ),
                                );
                                if (ok != true || !context.mounted) return;
                                await runAction(
                                  context,
                                  () => ref
                                      .read(apiProvider)
                                      .configurator
                                      .deleteConfiguration(id: c.id),
                                );
                                ref.invalidate(savedConfigurationsProvider);
                              },
                            ),
                            onTap: () async {
                              await context.push(
                                '/configurator/configurations/${c.id}',
                              );
                              ref.invalidate(savedConfigurationsProvider);
                            },
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Starts a configuration of [model] for a customer (optional until quoting) and saves it.
class NewConfigurationDialog extends ConsumerStatefulWidget {
  const NewConfigurationDialog({
    super.key,
    required this.model,
    this.customerId,
  });

  final ModelSummary model;
  final String? customerId;

  @override
  ConsumerState<NewConfigurationDialog> createState() =>
      _NewConfigurationDialogState();
}

class _NewConfigurationDialogState
    extends ConsumerState<NewConfigurationDialog> {
  final _name = TextEditingController();
  Customer? _customer;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final id = widget.customerId;
    if (id != null) {
      ref.read(apiProvider).crm.getCustomer(id: id).then((c) {
        if (mounted) setState(() => _customer = c);
      }, onError: (_) {});
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final c = await ref
          .read(apiProvider)
          .configurator
          .createConfiguration(
            body: ConfigurationInput(
              modelId: widget.model.id,
              customerId: _customer?.id,
              name: _name.text.trim(),
            ),
          );
      if (mounted) Navigator.pop(context, c);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text('${l10n.newConfiguration}: ${widget.model.name}'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SearchPicker<Customer>(
              key: ValueKey(_customer?.id),
              label: l10n.customer,
              initial: _customer,
              display: (c) => '${c.code} · ${c.name}',
              search: (q) async =>
                  (await ref
                          .read(apiProvider)
                          .crm
                          .listCustomers(q: q, limit: 20))
                      .items,
              onSelected: (c) => setState(() => _customer = c),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              decoration: InputDecoration(labelText: l10n.name),
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
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _busy ? null : _create,
          child: Text(l10n.cfgStart),
        ),
      ],
    );
  }
}
