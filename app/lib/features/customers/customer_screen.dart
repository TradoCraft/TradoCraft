import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/api.dart';
import '../../app/workspace.dart';
import '../../shared/app_icons.dart';
import '../../shared/load_failed.dart';
import '../todo/object_todos_button.dart';
import 'customer_form.dart';

/// One customer as a page of its own (a workspace tab, `/customers/:id`), so other places (a
/// to-do, a link) can open it. It loads the customer and shows the same form as the list's dialog;
/// the list keeps opening its dialog.
class CustomerScreen extends ConsumerStatefulWidget {
  const CustomerScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<CustomerScreen> createState() => _CustomerScreenState();
}

class _CustomerScreenState extends ConsumerState<CustomerScreen> {
  Customer? _customer;
  String? _error;
  bool _missing = false;
  int _version = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = await ref.read(apiProvider).crm.getCustomer(id: widget.id);
      if (!mounted) return;
      setState(() {
        _customer = c;
        _error = null;
      });
      TabScope.reportTitle(context, c.name);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = errorMessage(e);
        _missing = errorStatus(e) == 404;
      });
    }
  }

  void _close() => context.canPop() ? context.pop() : context.go('/customers');

  @override
  Widget build(BuildContext context) {
    final c = _customer;
    if (c == null) {
      return Scaffold(
        body: _error == null
            ? const Center(child: CircularProgressIndicator())
            : LoadFailedView(
                message: _error!,
                leaveTo: '/customers',
                notFound: _missing,
                todoKind: TodoLinkKind.customer,
                todoId: widget.id,
              ),
      );
    }
    final canWrite = can(ref, 'customers.write');
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                IconButton(
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: _close,
                  icon: const Icon(AppIcons.arrowBack),
                ),
                Text(c.name, style: Theme.of(context).textTheme.headlineSmall),
                ObjectTodosButton(
                  kind: TodoLinkKind.customer,
                  id: c.id,
                  label: c.name,
                ),
              ],
            ),
          ),
          Expanded(
            child: CustomerForm(
              // A saved customer rebuilds the form with the new values.
              key: ValueKey(_version),
              customer: c,
              readOnly: !canWrite,
              screen: true,
              onDone: (saved) {
                if (saved == null) {
                  _close();
                } else {
                  setState(() {
                    _customer = saved;
                    _version++;
                  });
                  TabScope.reportTitle(context, saved.name);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
