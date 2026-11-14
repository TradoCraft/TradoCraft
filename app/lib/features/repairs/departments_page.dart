import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../helpdesk/ticket_screen.dart' show usersProvider;
import 'repairs_page.dart' show departmentsProvider;
import '../../shared/app_icons.dart';

/// The workshop departments. Only the site admin gets here: they create the departments repairs
/// are routed to, and say which colleagues belong to each.
class DepartmentsPage extends ConsumerWidget {
  const DepartmentsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final departments = ref.watch(departmentsProvider);
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/repairs'),
        ),
        title: Text(l.departments),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(AppIcons.add),
        label: Text(l.newDepartment),
        onPressed: () async {
          if (await showDepartmentForm(context) == true) {
            ref.invalidate(departmentsProvider);
          }
        },
      ),
      body: departments.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(errorMessage(e))),
        data: (list) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(l.departmentsHelp, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            for (final d in list)
              Card(
                child: ListTile(
                  onTap: () async {
                    if (await showDepartmentForm(context, department: d) ==
                        true) {
                      ref.invalidate(departmentsProvider);
                    }
                  },
                  leading: CircleAvatar(
                    child: Text(d.code.characters.take(2).toString()),
                  ),
                  title: Text(
                    d.active ? d.name : '${d.name} (${l.inactive})',
                    style: d.active
                        ? null
                        : TextStyle(color: theme.colorScheme.outline),
                  ),
                  subtitle: Text(
                    d.members.isEmpty
                        ? '—'
                        : d.members.map((m) => m.displayName).join(', '),
                  ),
                  trailing: Chip(
                    label: Text(l.openRepairsCount('${d.openRepairs}')),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Future<bool?> showDepartmentForm(
  BuildContext context, {
  Department? department,
}) => showDialog<bool>(
  context: context,
  builder: (_) => _DepartmentForm(department: department),
);

class _DepartmentForm extends ConsumerStatefulWidget {
  const _DepartmentForm({this.department});
  final Department? department;

  @override
  ConsumerState<_DepartmentForm> createState() => _DepartmentFormState();
}

class _DepartmentFormState extends ConsumerState<_DepartmentForm> {
  late final d = widget.department;
  late final _code = TextEditingController(text: d?.code);
  late final _name = TextEditingController(text: d?.name);
  late final _order = TextEditingController(text: '${d?.sortOrder ?? 0}');
  late bool _active = d?.active ?? true;
  late final Set<String> _members = {...?d?.members.map((m) => m.userId)};
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    for (final t in [_code, _name, _order]) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final input = DepartmentInput(
      code: _code.text.trim(),
      name: _name.text.trim(),
      sortOrder: int.tryParse(_order.text.trim()) ?? 0,
      active: _active,
      memberUserIds: _members.toList(),
    );
    try {
      final api = ref.read(apiProvider).repairs;
      d == null
          ? await api.createDepartment(body: input)
          : await api.updateDepartment(id: d!.id, body: input);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final users = ref.watch(usersProvider).value ?? const [];
    const gap = SizedBox(height: 12, width: 12);
    return AlertDialog(
      title: Text(d == null ? l.newDepartment : l.editDepartment),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 150,
                    child: TextField(
                      controller: _code,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(labelText: l.departmentCode),
                    ),
                  ),
                  gap,
                  Expanded(
                    child: TextField(
                      controller: _name,
                      decoration: InputDecoration(labelText: l.name),
                    ),
                  ),
                ],
              ),
              gap,
              Text(
                l.departmentMembers,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              Wrap(
                spacing: 8,
                children: [
                  for (final u in users)
                    FilterChip(
                      label: Text(u.displayName),
                      selected: _members.contains(u.id),
                      onSelected: (on) => setState(
                        () => on ? _members.add(u.id) : _members.remove(u.id),
                      ),
                    ),
                ],
              ),
              if (d != null)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.active),
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                ),
              if (_error != null) ...[
                gap,
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(onPressed: _busy ? null : _save, child: Text(l.save)),
      ],
    );
  }
}
