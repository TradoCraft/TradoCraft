import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/generated/export.dart';
import '../l10n/l10n.dart';
import 'portal_state.dart';

/// The one-click unsubscribe a recipient reaches from the link at the bottom of a mailing.
/// No sign-in: the link carries the token. Opening the page changes nothing; the address is only
/// unsubscribed when the recipient confirms.
class PortalUnsubscribePage extends ConsumerStatefulWidget {
  const PortalUnsubscribePage({super.key, required this.token});
  final String? token;

  @override
  ConsumerState<PortalUnsubscribePage> createState() =>
      _PortalUnsubscribePageState();
}

class _PortalUnsubscribePageState extends ConsumerState<PortalUnsubscribePage> {
  UnsubscribeInfo? _info;
  String? _error;
  bool _done = false;
  bool _invalid = false;
  bool _busy = false;

  CrmClient get _api => TradocraftApi(ref.read(portalDioProvider)).crm;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = widget.token;
    if (token == null) {
      setState(() => _invalid = true);
      return;
    }
    try {
      final info = await _api.getMailingUnsubscribe(token: token);
      if (mounted) setState(() => _info = info);
    } catch (e) {
      if (!mounted) return;
      if (e is DioException && e.response?.statusCode == 404) {
        setState(() => _invalid = true);
      } else {
        setState(() => _error = portalError(e));
      }
    }
  }

  Future<void> _unsubscribe() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.mailingUnsubscribe(token: widget.token!);
      if (mounted) setState(() => _done = true);
    } catch (e) {
      if (mounted) setState(() => _error = portalError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    // Write to the recipient in the language of the mailing.
    return Localizations.override(
      context: context,
      locale: info == null ? null : Locale(info.language),
      child: Builder(builder: (context) => _page(context, info)),
    );
  }

  Widget _page(BuildContext context, UnsubscribeInfo? info) {
    final l = context.l10n;
    final theme = Theme.of(context);
    Widget body;
    if (info == null && _invalid) {
      body = Text(l.unsubscribeInvalid, style: theme.textTheme.titleMedium);
    } else if (info == null) {
      body = _error != null
          ? Text(_error!, style: TextStyle(color: theme.colorScheme.error))
          : const CircularProgressIndicator();
    } else if (_done) {
      body = Text(l.unsubscribeDone, style: theme.textTheme.titleLarge);
    } else if (info.unsubscribed) {
      body = Text(l.unsubscribeAlready, style: theme.textTheme.titleMedium);
    } else {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.unsubscribeTitle, style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(l.unsubscribeQuestion(info.companyName, info.email)),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton(
            key: const ValueKey('unsubscribe'),
            onPressed: _busy ? null : _unsubscribe,
            child: Text(l.unsubscribeAction),
          ),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(info?.companyName ?? l.portalTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(padding: const EdgeInsets.all(24), child: body),
        ),
      ),
    );
  }
}
