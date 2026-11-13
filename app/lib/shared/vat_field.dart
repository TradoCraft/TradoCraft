import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../api/generated/export.dart';
import '../l10n/l10n.dart';
import 'app_icons.dart';

/// Asks the server about a VAT number (ADR 0058): the customer or the supplier endpoint, with the
/// record's country and the record being edited already filled in by the caller.
typedef VatChecker = Future<VatCheck> Function({
  required String number,
  required bool lookup,
});

/// How long to wait after the last keystroke before checking the number.
const vatCheckDelay = Duration(milliseconds: 600);

/// A VAT number input that tells the user what is wrong with the number as they type (format,
/// check digits), which other records carry it, and, with the lookup button, what VIES knows.
///
/// All of it is advice: nothing blocks saving here, and a failing check says nothing. The server
/// refuses a wrong number on save and the form shows that message.
class VatNumberField extends StatefulWidget {
  const VatNumberField({
    super.key,
    required this.controller,
    required this.label,
    required this.check,
    this.onLookup,
    this.enabled = true,
    this.fieldKey,
  });

  /// The number being edited.
  final TextEditingController controller;

  /// The label of the input.
  final String label;

  /// Asks the server.
  final VatChecker check;

  /// Shows the lookup button when set. Called with VIES's answer when it knows the number; fills
  /// what it can of the form and returns true when it filled something.
  final bool Function(ViesLookup vies)? onLookup;

  /// False while saving, or read-only: the input and the button are off.
  final bool enabled;

  /// The key of the input itself, for tests.
  final Key? fieldKey;

  @override
  State<VatNumberField> createState() => _VatNumberFieldState();
}

class _VatNumberFieldState extends State<VatNumberField> {
  Timer? _timer;
  // Answers can arrive out of order: only the newest request may show its result.
  int _seq = 0;
  VatCheck? _result;
  ViesLookup? _vies;
  bool _filled = false;
  bool _busy = false;
  // The text the shown result is for.
  String _checked = '';

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    // An existing record: say at once whether its number is fine.
    if (widget.controller.text.trim().isNotEmpty) _schedule(Duration.zero);
  }

  @override
  void didUpdateWidget(VatNumberField old) {
    super.didUpdateWidget(old);
    // Another controller means another number: forget what was said about the old one.
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      _seq++;
      _result = null;
      _vies = null;
      _filled = false;
      _busy = false;
      _checked = '';
      if (widget.controller.text.trim().isNotEmpty) _schedule(Duration.zero);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _timer?.cancel();
    super.dispose();
  }

  void _changed() {
    final text = widget.controller.text.trim();
    if (text == _checked) return;
    // What VIES said was about the old number.
    if (_vies != null || _filled) {
      setState(() {
        _vies = null;
        _filled = false;
      });
    }
    _schedule(vatCheckDelay);
  }

  void _schedule(Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, () => _run(lookup: false));
  }

  Future<void> _run({required bool lookup}) async {
    _timer?.cancel();
    final text = widget.controller.text.trim();
    final seq = ++_seq;
    if (text.isEmpty) {
      setState(() {
        _result = null;
        _vies = null;
        _filled = false;
        _busy = false;
        _checked = '';
      });
      return;
    }
    if (lookup) setState(() => _busy = true);
    try {
      final r = await widget.check(number: text, lookup: lookup);
      if (!mounted || seq != _seq) return;
      var filled = false;
      if (lookup && r.vies?.state == ViesState.valid) {
        filled = widget.onLookup?.call(r.vies!) ?? false;
      }
      setState(() {
        _result = r;
        _checked = text;
        _busy = false;
        if (lookup) {
          _vies = r.vies;
          _filled = filled;
        }
      });
    } catch (_) {
      // Advice only: a check that fails says nothing, and saving reports real problems.
      if (mounted && seq == _seq) setState(() => _busy = false);
    }
  }

  Widget _line(
    BuildContext context,
    Key key,
    String text, {
    Color? color,
    IconData? icon,
  }) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: color);
    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 4),
      child: Row(
        key: key,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
          ],
          Expanded(child: Text(text, style: style)),
        ],
      ),
    );
  }

  String _records(AppLocalizations l, List<VatDuplicate> duplicates) {
    final shown = [
      for (final d in duplicates.take(3))
        d.active ? '${d.code} ${d.name}' : l.vatInactive('${d.code} ${d.name}'),
    ];
    if (duplicates.length > 3) shown.add('…');
    return shown.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final r = _result;
    final text = widget.controller.text.trim();
    final lines = <Widget>[];
    if (r != null && text.isNotEmpty) {
      switch (r.status) {
        case VatStatus.valid:
          lines.add(
            _line(
              context,
              const ValueKey('vat-status'),
              l.vatValid,
              icon: AppIcons.verified,
            ),
          );
        case VatStatus.formatOk:
          lines.add(
            _line(context, const ValueKey('vat-status'), l.vatFormatOk),
          );
        case VatStatus.badFormat:
          lines.add(
            _line(
              context,
              const ValueKey('vat-status'),
              l.vatBadFormat,
              color: scheme.error,
              icon: AppIcons.warningAmber,
            ),
          );
        case VatStatus.badChecksum:
          lines.add(
            _line(
              context,
              const ValueKey('vat-status'),
              l.vatBadChecksum,
              color: scheme.error,
              icon: AppIcons.warningAmber,
            ),
          );
        case VatStatus.notChecked:
          lines.add(
            _line(context, const ValueKey('vat-status'), l.vatNotChecked),
          );
        default:
          break;
      }
      if (r.duplicates.isNotEmpty) {
        lines.add(
          _line(
            context,
            const ValueKey('vat-duplicates'),
            l.vatDuplicates(_records(l, r.duplicates)),
            color: scheme.tertiary,
            icon: AppIcons.info,
          ),
        );
      }
    }
    final v = _vies;
    if (v != null) {
      switch (v.state) {
        case ViesState.valid:
          lines.add(
            _line(
              context,
              const ValueKey('vat-vies'),
              l.viesValid,
              icon: AppIcons.verified,
            ),
          );
          // Only say what happened: filled something, or the member state had nothing to give.
          // Details that were there but not used (the fields already had text) need no remark.
          final detail = _filled
              ? l.viesFilled
              : (v.name == null && v.address == null)
              ? l.viesNoDetails
              : null;
          if (detail != null) {
            lines.add(
              _line(context, const ValueKey('vat-vies-detail'), detail),
            );
          }
        case ViesState.invalid:
          lines.add(
            _line(
              context,
              const ValueKey('vat-vies'),
              l.viesInvalid,
              color: scheme.error,
              icon: AppIcons.warningAmber,
            ),
          );
        case ViesState.unavailable:
          lines.add(
            _line(
              context,
              const ValueKey('vat-vies'),
              v.reason == 'disabled'
                  ? l.viesDisabled
                  : l.viesUnavailable(v.reason ?? ''),
              color: scheme.tertiary,
              icon: AppIcons.info,
            ),
          );
        default:
          break;
      }
    }
    final canLookup = widget.onLookup != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: widget.fieldKey,
          controller: widget.controller,
          enabled: widget.enabled,
          decoration: InputDecoration(
            labelText: widget.label,
            suffixIcon: canLookup
                ? IconButton(
                    key: const ValueKey('vat-lookup'),
                    tooltip: l.vatLookup,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(AppIcons.search),
                    onPressed: widget.enabled && !_busy && text.isNotEmpty
                        ? () => _run(lookup: true)
                        : null,
                  )
                : null,
          ),
        ),
        ...lines,
      ],
    );
  }
}
