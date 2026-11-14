import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/generated/export.dart';
import '../l10n/l10n.dart';
import 'portal_state.dart';
import '../shared/app_icons.dart';

/// The one-click satisfaction survey a customer reaches from the e-mail after a ticket was closed.
/// No sign-in: the link carries a single-use token. Opening the page changes nothing; the rating
/// is recorded when the customer confirms it.
class PortalCsatPage extends ConsumerStatefulWidget {
  const PortalCsatPage({super.key, required this.link});
  final CsatLink? link;

  @override
  ConsumerState<PortalCsatPage> createState() => _PortalCsatPageState();
}

class _PortalCsatPageState extends ConsumerState<PortalCsatPage> {
  CsatInfo? _info;
  String? _error;
  String? _rating;
  bool _done = false;
  bool _unknown = false;
  bool _busy = false;
  final _comment = TextEditingController();

  HelpdeskClient get _api =>
      TradocraftApi(ref.read(portalDioProvider)).helpdesk;

  @override
  void initState() {
    super.initState();
    _rating = widget.link?.rating;
    _load();
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final link = widget.link;
    if (link == null) {
      setState(() => _unknown = true);
      return;
    }
    try {
      final info = await _api.getCsat(token: link.token);
      if (mounted) setState(() => _info = info);
    } catch (e) {
      if (!mounted) return;
      // An unknown token reads like an expired one: there is nothing to answer.
      if (e is DioException && e.response?.statusCode == 404) {
        setState(() => _unknown = true);
      } else {
        setState(() => _error = portalError(e));
      }
    }
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.rateCsat(
        token: widget.link!.token,
        body: CsatInput(rating: _rating!, comment: _comment.text.trim()),
      );
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
    // Write to the customer in the language of the ticket.
    return Localizations.override(
      context: context,
      locale: info == null ? null : Locale(info.language),
      child: Builder(builder: (context) => _page(context, info)),
    );
  }

  Widget _page(BuildContext context, CsatInfo? info) {
    final l = context.l10n;
    final theme = Theme.of(context);
    Widget body;
    if (info == null && _unknown) {
      body = Text(l.csatExpired, style: theme.textTheme.titleMedium);
    } else if (info == null) {
      body = _error != null
          ? Text(_error!, style: TextStyle(color: theme.colorScheme.error))
          : const CircularProgressIndicator();
    } else if (_done) {
      body = Text(l.csatThanks, style: theme.textTheme.titleLarge);
    } else if (info.state == 'rated') {
      body = Text(l.csatAlready, style: theme.textTheme.titleMedium);
    } else if (info.state == 'expired') {
      body = Text(l.csatExpired, style: theme.textTheme.titleMedium);
    } else {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.csatQuestion(info.ticketNumber),
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(info.subject, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 16),
          SegmentedButton<String>(
            emptySelectionAllowed: true,
            segments: [
              ButtonSegment(
                value: 'good',
                icon: const Icon(AppIcons.sentimentSatisfiedAlt),
                label: Text(l.csatGood, key: const ValueKey('rate-good')),
              ),
              ButtonSegment(
                value: 'bad',
                icon: const Icon(AppIcons.sentimentDissatisfied),
                label: Text(l.csatBad, key: const ValueKey('rate-bad')),
              ),
            ],
            selected: {?_rating},
            onSelectionChanged: (s) =>
                setState(() => _rating = s.isEmpty ? null : s.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _comment,
            minLines: 3,
            maxLines: 6,
            decoration: InputDecoration(labelText: l.csatComment),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          const SizedBox(height: 12),
          FilledButton(
            key: const ValueKey('send-rating'),
            onPressed: _busy || _rating == null ? null : _send,
            child: Text(l.send),
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
