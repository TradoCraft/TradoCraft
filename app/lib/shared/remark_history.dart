import 'package:material_ui/material_ui.dart';

import '../app/api.dart';
import '../l10n/l10n.dart';
import 'format.dart';

/// The scopes of the remark history, in tab order: quotations of this customer, quotations in the
/// language of this quotation, all quotations.
const remarkHistoryScopes = ['customer', 'language', 'all'];

/// Loads the earlier remarks of a product for one scope (`customer`, `language` or `all`).
typedef RemarkHistoryLoader = Future<List<RemarkHistoryEntry>> Function(
  String scope,
);

/// Opens the history of earlier remarks in a dialog with a tab per scope and returns the text the
/// user taps (null when the dialog is dismissed). [load] answers a scope that cannot be asked for
/// (no customer chosen yet) with an empty list.
Future<String?> showRemarkHistory(
  BuildContext context, {
  required String title,
  required RemarkHistoryLoader load,
}) => showDialog<String>(
  context: context,
  builder: (_) => RemarkHistoryPanel(title: title, load: load),
);

/// Dialog listing earlier remarks of a product by scope; tapping one returns its text.
class RemarkHistoryPanel extends StatelessWidget {
  const RemarkHistoryPanel({
    super.key,
    required this.title,
    required this.load,
  });

  final String title;
  final RemarkHistoryLoader load;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final labels = [
      l.remarkHistoryThisCustomer,
      l.remarkHistoryThisLanguage,
      l.remarkHistoryAll,
    ];
    return DefaultTabController(
      length: remarkHistoryScopes.length,
      child: AlertDialog(
        key: const ValueKey('remark-history'),
        title: Text(title),
        content: SizedBox(
          width: 520,
          height: 360,
          child: Column(
            children: [
              TabBar(
                tabs: [
                  for (final (i, scope) in remarkHistoryScopes.indexed)
                    Tab(key: ValueKey('remark-tab-$scope'), text: labels[i]),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    for (final scope in remarkHistoryScopes)
                      _ScopeList(scope: scope, load: load),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.cancel),
          ),
        ],
      ),
    );
  }
}

/// The remarks of one scope, loaded once.
class _ScopeList extends StatefulWidget {
  const _ScopeList({required this.scope, required this.load});
  final String scope;
  final RemarkHistoryLoader load;

  @override
  State<_ScopeList> createState() => _ScopeListState();
}

/// State of [_ScopeList]: keeps the loaded entries while switching tabs.
class _ScopeListState extends State<_ScopeList>
    with AutomaticKeepAliveClientMixin {
  late final Future<List<RemarkHistoryEntry>> _entries = widget.load(
    widget.scope,
  );

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<List<RemarkHistoryEntry>>(
      future: _entries,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text(errorMessage(snap.error!)));
        }
        final entries = snap.data;
        if (entries == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (entries.isEmpty) {
          return Center(child: Text(context.l10n.remarkHistoryEmpty));
        }
        return ListView(
          key: ValueKey('remark-list-${widget.scope}'),
          children: [
            for (final e in entries)
              ListTile(
                dense: true,
                title: Text(e.text),
                subtitle: Text(
                  '${context.l10n.remarkHistoryUsed(e.useCount, e.lastQuotationNumber)}'
                  ' · ${date(e.lastUsed)}',
                ),
                onTap: () => Navigator.pop(context, e.text),
              ),
          ],
        );
      },
    );
  }
}
