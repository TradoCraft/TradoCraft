import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../api/generated/export.dart';
import '../l10n/l10n.dart';
import '../shared/attachments.dart';
import 'portal_help.dart' show PortalKbSuggestions;
import 'portal_state.dart';
import '../shared/app_icons.dart';

final _when = DateFormat('dd/MM/yyyy HH:mm');

/// Ticket categories a customer can choose from.
const portalCategories = ['question', 'service', 'complaint', 'other'];

// ---------------------------------------------------------------------------------------------
// Login
// ---------------------------------------------------------------------------------------------

/// Asks for an e-mail address and sends a login link; or, when opened from the link
/// (`/login#token=...`), exchanges the token for a session.
class PortalLoginPage extends ConsumerStatefulWidget {
  const PortalLoginPage({super.key, this.linkToken});

  /// The token from the login link; read from the address bar when not given.
  final String? linkToken;

  @override
  ConsumerState<PortalLoginPage> createState() => _PortalLoginPageState();
}

class _PortalLoginPageState extends ConsumerState<PortalLoginPage> {
  final _email = TextEditingController();
  bool _busy = false;
  bool _sent = false;
  bool _linkInvalid = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // The token was read at start-up (see portal_main): by now the router has rewritten the
    // address and the fragment is gone.
    final token = widget.linkToken ?? ref.read(portalLinkTokenProvider);
    if (token != null && token.isNotEmpty) {
      _busy = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _exchange(token));
    }
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _exchange(String token) async {
    // A link works once: never try it again, whatever the outcome.
    ref.read(portalLinkTokenProvider.notifier).clear();
    try {
      final session = await ref
          .read(portalApiProvider)
          .createSession(body: SessionInput(token: token));
      ref
          .read(portalLocaleProvider.notifier)
          .set(Locale(session.profile.effectiveLanguage));
      await ref.read(portalTokenProvider.notifier).set(session.token);
      ref.invalidate(portalProfileProvider);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _linkInvalid = true;
        });
      }
    }
  }

  Future<void> _request() async {
    final email = _email.text.trim();
    if (!email.contains('@')) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(portalApiProvider)
          .requestLoginLink(
            body: LoginLinkInput(companyId: portalCompanyId, email: email),
          );
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) setState(() => _error = portalError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final locale = ref.watch(portalLocaleProvider);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l.portalTitle, style: theme.textTheme.headlineMedium),
                const SizedBox(height: 16),
                if (_busy && !_sent && _email.text.isEmpty && !_linkInvalid)
                  Row(
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Text(l.signingIn),
                    ],
                  )
                else if (_sent)
                  Text(l.loginLinkSent)
                else ...[
                  if (_linkInvalid)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        l.loginLinkInvalid,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  Text(l.portalSignInIntro),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _email,
                    autofocus: true,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: InputDecoration(labelText: l.email),
                    onSubmitted: (_) => _request(),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _busy ? null : _request,
                    child: Text(l.sendLoginLink),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _error!,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                ],
                const SizedBox(height: 24),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final code in languageCodes)
                      ChoiceChip(
                        label: Text(languageName(code)),
                        selected: locale?.languageCode == code,
                        onSelected: (_) => ref
                            .read(portalLocaleProvider.notifier)
                            .set(Locale(code)),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Tickets
// ---------------------------------------------------------------------------------------------

Widget _statusChip(BuildContext context, String status) {
  final theme = Theme.of(context);
  final waiting = status == 'pending_customer';
  return Chip(
    label: Text(context.l10n.portalTicketStatus(status)),
    backgroundColor: waiting ? theme.colorScheme.tertiaryContainer : null,
    visualDensity: VisualDensity.compact,
  );
}

class PortalTicketsPage extends ConsumerWidget {
  const PortalTicketsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final tickets = ref.watch(portalTicketsProvider);
    final me = ref.watch(portalProfileProvider).value;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/tickets/new'),
        icon: const Icon(AppIcons.add),
        label: Text(l.newTicket),
      ),
      body: tickets.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(portalError(e))),
        data: (list) => list.isEmpty
            ? Center(child: Text(l.noTicketsYet))
            : RefreshIndicator(
                onRefresh: () async =>
                    ref.refresh(portalTicketsProvider.future),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                  children: [
                    Text(
                      l.myTickets,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    for (final t in list)
                      Card(
                        child: ListTile(
                          onTap: () => context.go('/tickets/${t.id}'),
                          title: Text('${t.number}  ${t.subject}'),
                          subtitle: Text(
                            [
                              toBeginningOfSentenceCase(
                                l.ticketCategory(t.category),
                              ),
                              // With the "all tickets" scope, colleagues' tickets show who raised them.
                              if (me != null &&
                                  t.contactName.isNotEmpty &&
                                  t.contactName != me.fullName)
                                l.raisedBy(t.contactName),
                              _when.format(t.updatedAt.toLocal()),
                            ].join('  ·  '),
                          ),
                          trailing: _statusChip(context, t.status),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

class PortalTicketPage extends ConsumerStatefulWidget {
  const PortalTicketPage({super.key, required this.id, this.pickFiles});
  final String id;

  /// How files are chosen; replaceable in tests.
  final AttachmentPicker? pickFiles;

  @override
  ConsumerState<PortalTicketPage> createState() => _PortalTicketPageState();
}

class _PortalTicketPageState extends ConsumerState<PortalTicketPage> {
  final _body = TextEditingController();
  bool _busy = false;
  String? _error;
  List<FileInfo> _attached = [];

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_body.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(portalApiProvider)
          .addPortalMessage(
            id: widget.id,
            body: MessageInput(
              body: _body.text.trim(),
              attachmentIds: [for (final f in _attached) f.id],
            ),
          );
      _body.clear();
      _attached = [];
      ref.invalidate(portalTicketProvider(widget.id));
      ref.invalidate(portalTicketsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(context.l10n.messageSent)));
      }
    } catch (e) {
      if (mounted) setState(() => _error = portalError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final detail = ref.watch(portalTicketProvider(widget.id));
    return detail.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(portalError(e))),
      data: (d) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 16, 0),
            child: Row(
              children: [
                IconButton(
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: () => context.go('/'),
                  icon: const Icon(AppIcons.arrowBack),
                ),
                Expanded(
                  child: Text(
                    '${d.ticket.number}  ${d.ticket.subject}',
                    style: theme.textTheme.titleLarge,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _statusChip(context, d.ticket.status),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final m in d.messages)
                  _MessageBubble(
                    message: m,
                    dio: ref.read(portalDioProvider),
                    ticketId: widget.id,
                  ),
              ],
            ),
          ),
          Material(
            color: theme.colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _body,
                    minLines: 3,
                    maxLines: 8,
                    decoration: InputDecoration(labelText: l.yourMessage),
                  ),
                  const SizedBox(height: 8),
                  AttachmentComposer(
                    dio: ref.read(portalDioProvider),
                    uploadPath:
                        '/api/v1/portal/tickets/${widget.id}/attachments',
                    files: _attached,
                    pick: widget.pickFiles ?? pickAttachmentFiles,
                    onChanged: (f) => setState(() => _attached = f),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _error!,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _send,
                      icon: const Icon(AppIcons.send),
                      label: Text(l.send),
                    ),
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

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.dio,
    required this.ticketId,
  });
  final PortalMessage message;
  final Dio dio;
  final String ticketId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mine = message.direction == 'incoming';
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Card(
          color: mine
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${message.authorName}  ·  ${_when.format(message.createdAt.toLocal())}',
                  style: theme.textTheme.labelMedium,
                ),
                const SizedBox(height: 6),
                SelectableText(message.body),
                AttachmentChips(
                  files: message.attachments,
                  dio: dio,
                  pathFor: (id) =>
                      '/api/v1/portal/tickets/$ticketId/attachments/$id',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PortalNewTicketPage extends ConsumerStatefulWidget {
  const PortalNewTicketPage({super.key});

  @override
  ConsumerState<PortalNewTicketPage> createState() =>
      _PortalNewTicketPageState();
}

class _PortalNewTicketPageState extends ConsumerState<PortalNewTicketPage> {
  final _subject = TextEditingController();
  final _body = TextEditingController();
  String _category = 'question';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = context.l10n;
    if (_subject.text.trim().isEmpty || _body.text.trim().isEmpty) {
      setState(() => _error = l.required);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final d = await ref
          .read(portalApiProvider)
          .createPortalTicket(
            body: NewTicket(
              subject: _subject.text.trim(),
              category: _category,
              body: _body.text.trim(),
            ),
          );
      ref.invalidate(portalTicketsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.ticketOpened)));
      context.go('/tickets/${d.ticket.id}');
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
              onPressed: () => context.go('/'),
              icon: const Icon(AppIcons.arrowBack),
            ),
            Text(l.newTicket, style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
        gap,
        TextField(
          controller: _subject,
          decoration: InputDecoration(labelText: l.subject),
        ),
        PortalKbSuggestions(controller: _subject),
        gap,
        DropdownButtonFormField<String>(
          initialValue: _category,
          decoration: InputDecoration(labelText: l.category),
          items: [
            for (final c in portalCategories)
              DropdownMenuItem(
                value: c,
                child: Text(toBeginningOfSentenceCase(l.ticketCategory(c))),
              ),
          ],
          onChanged: (v) => setState(() => _category = v!),
        ),
        gap,
        TextField(
          controller: _body,
          minLines: 6,
          maxLines: 14,
          decoration: InputDecoration(labelText: l.yourMessage),
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
            onPressed: _busy ? null : _save,
            child: Text(l.send),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Profile
// ---------------------------------------------------------------------------------------------

/// How we write to the person: their language (or the company's), form of address and title.
class PortalProfilePage extends ConsumerStatefulWidget {
  const PortalProfilePage({super.key});

  @override
  ConsumerState<PortalProfilePage> createState() => _PortalProfilePageState();
}

class _PortalProfilePageState extends ConsumerState<PortalProfilePage> {
  String? _language;
  String? _addressForm;
  String? _title;
  bool _loaded = false;
  bool _busy = false;
  String? _error;

  void _load(PortalProfile p) {
    if (_loaded) return;
    _loaded = true;
    _language = p.language;
    _addressForm = p.addressForm;
    _title = p.title;
  }

  Future<void> _save(PortalProfile p) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updated = await ref
          .read(portalApiProvider)
          .updateMe(
            body: ProfileInput(
              language: _language,
              addressForm: _addressForm ?? p.addressForm,
              title: _title ?? p.title,
            ),
          );
      ref.invalidate(portalProfileProvider);
      ref
          .read(portalLocaleProvider.notifier)
          .set(Locale(updated.effectiveLanguage));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(context.l10n.saved)));
      }
    } catch (e) {
      if (mounted) setState(() => _error = portalError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final profile = ref.watch(portalProfileProvider);
    const gap = SizedBox(height: 12);
    return profile.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(portalError(e))),
      data: (p) {
        _load(p);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: () => context.go('/'),
                  icon: const Icon(AppIcons.arrowBack),
                ),
                Text(l.myProfile, style: theme.textTheme.titleLarge),
              ],
            ),
            gap,
            Text(p.fullName, style: theme.textTheme.titleMedium),
            Text(
              [
                p.customerName,
                if (p.jobTitle.isNotEmpty) p.jobTitle,
                if (p.email != null) p.email!,
              ].join('  ·  '),
            ),
            gap,
            Text(l.profileHelp),
            gap,
            DropdownButtonFormField<String?>(
              isExpanded: true,
              initialValue: _language,
              decoration: InputDecoration(labelText: l.language),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(
                    l.languageSameAsCustomer(languageName(p.customerLanguage)),
                  ),
                ),
                for (final c in languageCodes)
                  DropdownMenuItem<String?>(
                    value: c,
                    child: Text(languageName(c)),
                  ),
              ],
              onChanged: (v) => setState(() => _language = v),
            ),
            gap,
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _addressForm,
              decoration: InputDecoration(labelText: l.addressForm),
              items: [
                DropdownMenuItem(value: 'formal', child: Text(l.addressFormal)),
                DropdownMenuItem(
                  value: 'informal',
                  child: Text(l.addressInformal),
                ),
              ],
              onChanged: (v) => setState(() => _addressForm = v),
            ),
            gap,
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _title,
              decoration: InputDecoration(labelText: l.personTitle),
              items: [
                for (final t in ['none', 'mr', 'ms'])
                  DropdownMenuItem(
                    value: t,
                    child: Text(l.personTitleLabel(t)),
                  ),
              ],
              onChanged: (v) => setState(() => _title = v),
            ),
            gap,
            Text(
              l.greetingPreview(p.greeting),
              style: theme.textTheme.bodySmall,
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            gap,
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed: _busy ? null : () => _save(p),
                child: Text(l.save),
              ),
            ),
          ],
        );
      },
    );
  }
}
