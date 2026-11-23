import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/actions.dart';
import '../../shared/app_icons.dart';
import '../../shared/attachments.dart' show fileSize;
import '../../shared/csv_transfer.dart' show PickedFile;
import '../price_lists/price_lists_api.dart';

/// Lets the person choose a logo file; null when they cancel. Replaced in tests.
typedef LogoPicker = Future<PickedFile?> Function();

final logoPickerProvider = Provider<LogoPicker>((_) => () async {
  final f = await openFile(
    acceptedTypeGroups: const [
      XTypeGroup(
        label: 'PNG, JPEG, SVG',
        extensions: ['png', 'jpg', 'jpeg', 'svg'],
        mimeTypes: ['image/png', 'image/jpeg', 'image/svg+xml'],
        uniformTypeIdentifiers: ['public.png', 'public.jpeg', 'public.svg-image'],
      ),
    ],
  );
  if (f == null) return null;
  return (name: f.name, bytes: await f.readAsBytes());
});

/// The company logo for administrators: preview, upload with type and size checks, remove.
class CompanyLogoPage extends ConsumerStatefulWidget {
  const CompanyLogoPage({super.key});

  @override
  ConsumerState<CompanyLogoPage> createState() => _CompanyLogoPageState();
}

class _CompanyLogoPageState extends ConsumerState<CompanyLogoPage> {
  String? _error;
  bool _busy = false;

  void _refresh() {
    ref.invalidate(companyLogoBytesProvider);
    ref.invalidate(companyLogoInfoProvider);
  }

  Future<void> _choose() async {
    final l = context.l10n;
    final PickedFile? picked;
    try {
      picked = await ref.read(logoPickerProvider)();
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
      return;
    }
    if (picked == null || !mounted) return;
    final file = picked;
    // The server checks again; these checks only save a round trip.
    if (file.bytes.length > maxLogoBytes) {
      setState(() => _error = l.logoTooBig);
      return;
    }
    if (logoContentType(file.bytes) == null) {
      setState(() => _error = l.logoBadType);
      return;
    }
    setState(() {
      _error = null;
      _busy = true;
    });
    final ok = await runAction(
      context,
      () async => uploadLogo(ref.read(dioProvider), file.bytes),
      success: l.logoSaved,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) _refresh();
  }

  Future<void> _remove() async {
    final l = context.l10n;
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(l.logoRemoveConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            key: const ValueKey('logo-remove-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.logoRemove),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    setState(() => _busy = true);
    var ok = false;
    try {
      ok = await runAction(
        context,
        () => ref.read(apiProvider).core.deleteLogo(),
        success: l.logoRemoved,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (ok && mounted) _refresh();
  }

  static const _autosaveOptions = [0, 1, 2, 5, 10, 15, 30];

  Future<void> _saveCompanySettings({
    required bool singleLine,
    required int autosaveMinutes,
  }) async {
    final l = context.l10n;
    setState(() => _busy = true);
    var ok = false;
    try {
      ok = await runAction(
        context,
        () => ref
            .read(dioProvider)
            .put<Map<String, dynamic>>(
              '/api/v1/admin/company/settings',
              data: {
                'quotation_single_line_items': singleLine,
                'autosave_minutes': autosaveMinutes,
              },
            ),
        success: l.quotationSettingsSaved,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (ok && mounted) ref.invalidate(meProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final logo = ref.watch(companyLogoBytesProvider);
    final company = ref.watch(meProvider).value?.company;
    final singleLine = company?.quotationSingleLineItems ?? true;
    final autosaveMinutes = company?.autosaveMinutes ?? 5;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(l.logoTitle, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(l.logoHint),
        const SizedBox(height: 12),
        logo.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Row(
            children: [
              Expanded(child: Text(errorMessage(e))),
              TextButton(
                key: const ValueKey('logo-retry'),
                onPressed: _refresh,
                child: Text(l.retry),
              ),
            ],
          ),
          data: (bytes) => bytes == null
              ? Text(l.logoNone, key: const ValueKey('logo-none'))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      key: const ValueKey('logo-preview'),
                      constraints: const BoxConstraints(
                        maxWidth: 320,
                        maxHeight: 160,
                      ),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      child: _preview(bytes),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${logoContentType(bytes) ?? ''} · ${fileSize(bytes.length)}',
                    ),
                  ],
                ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error!,
              key: const ValueKey('logo-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              key: const ValueKey('logo-choose'),
              onPressed: _busy ? null : _choose,
              icon: const Icon(AppIcons.fileUpload),
              label: Text(l.logoChoose),
            ),
            if (logo.value != null)
              OutlinedButton.icon(
                key: const ValueKey('logo-remove'),
                onPressed: _busy ? null : _remove,
                icon: const Icon(Icons.delete_outline),
                label: Text(l.logoRemove),
              ),
          ],
        ),
        const Divider(height: 32),
        Text(
          l.quotationLineLayoutTitle,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          key: const ValueKey('quotation-single-line-switch'),
          contentPadding: EdgeInsets.zero,
          title: Text(l.quotationSingleLineLabel),
          subtitle: Text(l.quotationSingleLineHelp),
          value: singleLine,
          onChanged: _busy
              ? null
              : (v) => _saveCompanySettings(
                  singleLine: v,
                  autosaveMinutes: autosaveMinutes,
                ),
        ),
        const Divider(height: 32),
        Text(
          l.autosaveTitle,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 4),
        Text(l.autosaveAdminHelp),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: DropdownButtonFormField<int>(
            key: const ValueKey('admin-autosave-minutes'),
            initialValue: _autosaveOptions.contains(autosaveMinutes)
                ? autosaveMinutes
                : 5,
            decoration: InputDecoration(labelText: l.autosaveTitle),
            items: [
              for (final m in _autosaveOptions)
                DropdownMenuItem(
                  value: m,
                  child: Text(m == 0 ? l.autosaveOff : l.autosaveMinutes(m)),
                ),
            ],
            onChanged: _busy
                ? null
                : (v) {
                    if (v != null) {
                      _saveCompanySettings(
                        singleLine: singleLine,
                        autosaveMinutes: v,
                      );
                    }
                  },
          ),
        ),
      ],
    );
  }

  Widget _preview(Uint8List bytes) => logoContentType(bytes) == 'image/svg+xml'
      ? SvgPicture.memory(bytes, fit: BoxFit.contain)
      : Image.memory(
          bytes,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const Icon(AppIcons.brokenImage),
        );
}
