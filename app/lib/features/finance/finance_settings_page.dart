import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/format.dart';

/// The Finance settings segment: the quantity and price tolerances of the three-way match.
class FinanceSettingsPage extends ConsumerStatefulWidget {
  /// Creates the page.
  const FinanceSettingsPage({super.key});

  @override
  ConsumerState<FinanceSettingsPage> createState() =>
      _FinanceSettingsPageState();
}

class _FinanceSettingsPageState extends ConsumerState<FinanceSettingsPage> {
  final _qty = TextEditingController();
  final _price = TextEditingController();
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _qty.dispose();
    _price.dispose();
    super.dispose();
  }

  void _apply(FinanceSettings s) {
    _qty.text = number(s.quantityTolerancePct);
    _price.text = number(s.priceTolerancePct);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final s = await ref.read(apiProvider).finance.getSettings();
      if (mounted) _apply(s);
    } catch (e) {
      if (mounted) setState(() => _loadError = errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// A percentage between 0 and 100 as a decimal string, or null when invalid.
  String? _pct(String text) {
    final v = parseDecimalInput(text);
    if (v == null) return null;
    final n = double.parse(v);
    return n < 0 || n > 100 ? null : v;
  }

  Future<void> _save() async {
    final l = context.l10n;
    final q = _pct(_qty.text);
    final p = _pct(_price.text);
    if (q == null || p == null) {
      setState(() => _error = l.finToleranceInvalid);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final s = await ref
          .read(apiProvider)
          .finance
          .updateSettings(
            body: UpdateFinanceSettingsInput(
              quantityTolerancePct: q,
              priceTolerancePct: p,
            ),
          );
      if (!mounted) return;
      _apply(s);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.finSettingsSaved)));
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    if (_loadError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_loadError!),
            TextButton(
              key: const ValueKey('fin-settings-retry'),
              onPressed: _load,
              child: Text(l.retry),
            ),
          ],
        ),
      );
    }
    if (_loading) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(l.finSettings, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(l.finSettingsHelp),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 320,
            child: Column(
              children: [
                TextField(
                  key: const ValueKey('fin-qty-tolerance'),
                  controller: _qty,
                  decoration: InputDecoration(
                    labelText: l.finQuantityTolerance,
                  ),
                  onChanged: (_) => setState(() => _error = null),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('fin-price-tolerance'),
                  controller: _price,
                  decoration: InputDecoration(labelText: l.finPriceTolerance),
                  onChanged: (_) => setState(() => _error = null),
                ),
              ],
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error!,
              key: const ValueKey('fin-settings-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            key: const ValueKey('fin-settings-save'),
            onPressed: _busy ? null : _save,
            child: Text(l.save),
          ),
        ),
      ],
    );
  }
}
