import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/app_icons.dart';
import '../../shared/search_picker.dart';
import 'runner_state.dart';
import 'widgets/field_widgets.dart';
import 'widgets/item_grid.dart';
import 'widgets/panels.dart';

/// Runs a saved configuration: the definition's form and item grids on the left, issues, lines
/// with prices and the trace of a line on the right (tabs on narrow screens). Every change is
/// evaluated on the server after a short pause.
class RunnerScreen extends ConsumerStatefulWidget {
  const RunnerScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<RunnerScreen> createState() => _RunnerScreenState();
}

class _RunnerScreenState extends ConsumerState<RunnerScreen>
    with TickerProviderStateMixin {
  final _focus = FieldFocus();
  final _name = TextEditingController();
  late final _panelTabs = TabController(length: 3, vsync: this);
  late final _narrowTabs = TabController(length: 4, vsync: this);
  List<int>? _selectedLine;
  bool _nameLoaded = false;

  @override
  void dispose() {
    _focus.dispose();
    _name.dispose();
    _panelTabs.dispose();
    _narrowTabs.dispose();
    super.dispose();
  }

  RunnerNotifier get _notifier => ref.read(runnerProvider(widget.id).notifier);

  void _showError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(errorMessage(e)),
        backgroundColor: Colors.red.shade700,
      ),
    );
  }

  Future<void> _save() async {
    try {
      await _notifier.save();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(context.l10n.cfgSaved)));
      }
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _quote() async {
    try {
      final r = await _notifier.quote();
      if (!mounted) return;
      final l10n = context.l10n;
      final n = r.quotation.number;
      final text = switch (r.action) {
        'updated' => l10n.cfgQuoteUpdated(n),
        'revised' => l10n.cfgQuoteRevised(n),
        _ => l10n.cfgQuoteCreated(n),
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
      context.push('/quotations/${r.quotation.id}');
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _upgrade() async {
    try {
      await _notifier.upgrade();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _close(bool dirty) async {
    if (dirty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(context.l10n.cfgDiscardChanges),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.l10n.cfgDiscard),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    if (context.canPop()) {
      context.pop(true);
    } else {
      context.go('/configurator');
    }
  }

  void _focusIssue(Issue issue, bool wide) {
    final ref = FieldRef.ofIssue(issue);
    if (ref == null) return;
    if (!wide) _narrowTabs.animateTo(0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_focus.focus(ref)) {
        // A computed value that is not shown, or a hidden field: nothing to focus.
      }
    });
  }

  void _selectLine(List<int> path, bool wide) {
    setState(() => _selectedLine = path);
    if (wide) {
      _panelTabs.animateTo(2);
    } else {
      _narrowTabs.animateTo(3);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(runnerProvider(widget.id));
    _notifier.language = Localizations.localeOf(context).languageCode;
    final l10n = context.l10n;
    if (s.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final def = s.definition;
    final config = s.configuration;
    if (def == null || config == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(s.loadError ?? ''),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => ref.invalidate(runnerProvider(widget.id)),
                child: Text(l10n.retry),
              ),
            ],
          ),
        ),
      );
    }
    if (!_nameLoaded) {
      _name.text = s.name;
      _nameLoaded = true;
    }
    final wide = MediaQuery.sizeOf(context).width >= 1100;
    final view = RunnerView(
      definition: def,
      inputs: s.inputs,
      index: s.index,
      actions: _notifier,
      displayUnits: s.displayUnits,
      focus: _focus,
    );
    final lines = s.evaluation?.lines ?? const <Line>[];
    final issues = s.evaluation?.issues ?? const <Issue>[];
    final selected = _selectedLine == null
        ? null
        : lineAt(lines, _selectedLine!);

    final form = RunnerForm(view: view);
    final issuesPanel = IssuesPanel(
      issues: issues,
      onTap: (i) => _focusIssue(i, wide),
    );
    final linesPanel = LinesPanel(
      lines: lines,
      selected: selected == null ? null : _selectedLine,
      onSelect: (p) => _selectLine(p, wide),
      pricing: s.pricing,
      positions: s.pricedPositions,
      pricingError: s.pricingError,
      hasCustomer: s.customerId != null,
    );
    final whyPanel = WhyPanel(line: selected);
    final errorCount = issues
        .where((i) => i.severity == IssueSeverity.error)
        .length;
    final issuesTab = Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.cfgIssues),
          if (issues.isNotEmpty) ...[
            const SizedBox(width: 6),
            Badge(
              label: Text('${issues.length}'),
              backgroundColor: errorCount > 0
                  ? Theme.of(context).colorScheme.error
                  : Colors.orange.shade800,
            ),
          ],
        ],
      ),
    );

    final body = wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: form),
              const VerticalDivider(width: 1),
              SizedBox(
                width: 440,
                child: Column(
                  children: [
                    TabBar(
                      controller: _panelTabs,
                      tabs: [
                        issuesTab,
                        Tab(text: l10n.cfgLines),
                        Tab(text: l10n.cfgWhy),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _panelTabs,
                        children: [issuesPanel, linesPanel, whyPanel],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          )
        : Column(
            children: [
              TabBar(
                controller: _narrowTabs,
                isScrollable: true,
                tabs: [
                  Tab(text: l10n.cfgInput),
                  issuesTab,
                  Tab(text: l10n.cfgLines),
                  Tab(text: l10n.cfgWhy),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _narrowTabs,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [form, issuesPanel, linesPanel, whyPanel],
                ),
              ),
            ],
          );

    final canQuote = can(ref, 'quotations.write');
    final hasErrors = errorCount > 0;
    final quoteBlocked = s.customerId == null
        ? l10n.cfgQuoteNeedsCustomer
        : hasErrors
        ? l10n.cfgQuoteBlocked
        : lines.isEmpty
        ? l10n.cfgNoLines
        : null;

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                IconButton(
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: () => _close(s.dirty),
                  icon: const Icon(AppIcons.arrowBack),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      config.modelName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      '${config.modelCode} · ${l10n.cfgRevision(config.revision)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: _name,
                    decoration: InputDecoration(
                      labelText: l10n.name,
                      isDense: true,
                    ),
                    onChanged: _notifier.setName,
                  ),
                ),
                if (s.customerId != null)
                  InputChip(
                    avatar: const Icon(AppIcons.business, size: 18),
                    label: Text(s.customerName ?? s.customerId!),
                    onDeleted: () => _notifier.setCustomer(null, null),
                  ),
                SizedBox(
                  width: 240,
                  child: SearchPicker<Customer>(
                    label: s.customerId == null
                        ? l10n.customer
                        : l10n.cfgChangeCustomer,
                    clearOnSelect: true,
                    display: (c) => '${c.code} · ${c.name}',
                    search: (q) async =>
                        (await ref
                                .read(apiProvider)
                                .crm
                                .listCustomers(q: q, limit: 20))
                            .items,
                    onSelected: (c) => _notifier.setCustomer(c.id, c.name),
                  ),
                ),
                if (s.dirty)
                  Text(
                    l10n.cfgUnsaved,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                OutlinedButton.icon(
                  onPressed: s.busy ? null : _save,
                  icon: const Icon(AppIcons.save),
                  label: Text(l10n.save),
                ),
                if (canQuote)
                  Tooltip(
                    message: quoteBlocked ?? '',
                    child: FilledButton.icon(
                      onPressed: s.busy || quoteBlocked != null || s.evaluating
                          ? null
                          : _quote,
                      icon: const Icon(AppIcons.requestQuote),
                      label: Text(
                        config.quotationId == null
                            ? l10n.cfgCreateQuotation
                            : l10n.cfgUpdateQuotation,
                      ),
                    ),
                  ),
                if (config.quotationId != null)
                  TextButton.icon(
                    onPressed: () =>
                        context.push('/quotations/${config.quotationId}'),
                    icon: const Icon(AppIcons.openInNew),
                    label: Text(config.quotationNumber ?? l10n.quotations),
                  ),
              ],
            ),
          ),
          // A subtle busy line while the server recalculates.
          SizedBox(
            height: 2,
            child: s.evaluating || s.busy
                ? const LinearProgressIndicator(minHeight: 2)
                : const SizedBox.shrink(),
          ),
          if (config.newerRevisionId != null)
            MaterialBanner(
              leading: const Icon(AppIcons.upgrade),
              content: Text(l10n.cfgNewerRevision),
              actions: [
                TextButton(
                  onPressed: s.busy ? null : _upgrade,
                  child: Text(l10n.cfgUpgrade),
                ),
              ],
            ),
          if (s.evalError != null)
            Container(
              color: Theme.of(context).colorScheme.errorContainer,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(AppIcons.syncProblem, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(l10n.cfgEvalFailed(s.evalError!))),
                  TextButton(
                    onPressed: _notifier.evaluate,
                    child: Text(l10n.retry),
                  ),
                ],
              ),
            ),
          const Divider(height: 1),
          Expanded(child: body),
        ],
      ),
    );
  }
}

/// Project form, a section per group and a grid per item table.
class RunnerForm extends StatelessWidget {
  const RunnerForm({super.key, required this.view});

  final RunnerView view;

  @override
  Widget build(BuildContext context) {
    final def = view.definition;
    final theme = Theme.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (def.description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(def.description, style: theme.textTheme.bodySmall),
          ),
        if (!def.project.isEmpty)
          ConfigForm(
            view: view,
            scope: def.project,
            refOf: FieldRef.project,
            sections: def.sections,
          ),
        if (!def.group.isEmpty)
          for (final g in view.index.groupNames)
            Card(
              key: ValueKey('group-section-$g'),
              margin: const EdgeInsets.only(top: 16),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${def.groupLabelIn(lang)}: ${g.isEmpty ? '—' : g}',
                      style: theme.textTheme.titleMedium,
                    ),
                    ConfigForm(
                      view: view,
                      scope: def.group,
                      refOf: (n) => FieldRef.group(g, n),
                    ),
                  ],
                ),
              ),
            ),
        for (final t in def.itemTables)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: ItemGrid(view: view, table: t),
          ),
      ],
    );
  }
}
