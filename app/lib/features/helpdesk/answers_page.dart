import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/app_icons.dart';

final _answersProvider = FutureProvider.autoDispose<List<PreparedAnswer>>(
  (ref) => ref.watch(apiProvider).helpdesk.listAnswers(),
);

/// Prepared answers for recurring questions, each with a text per language.
class AnswersPage extends ConsumerWidget {
  const AnswersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final answers = ref.watch(_answersProvider);
    final canWrite =
        ref.watch(meProvider).value?.permissions.contains('answers.write') ??
        false;
    Future<void> edit([PreparedAnswer? a]) async {
      final saved = await showDialog<bool>(
        context: context,
        builder: (_) => AnswerEditor(answer: a),
      );
      if (saved == true) ref.invalidate(_answersProvider);
    }

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              IconButton(
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go('/helpdesk'),
                icon: const Icon(AppIcons.arrowBack),
              ),
              Text(
                l.preparedAnswers,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const Spacer(),
              if (canWrite)
                FilledButton.icon(
                  onPressed: edit,
                  icon: const Icon(AppIcons.add),
                  label: Text(l.newAnswer),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(l.preparedAnswersHelp),
          ),
          answers.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text(errorMessage(e)),
            data: (list) => Column(
              children: [
                for (final a in list)
                  Card(
                    child: ListTile(
                      title: Text(a.name),
                      subtitle: Text(
                        [
                          a.code,
                          if (a.category != null) a.category!,
                          if (!a.active) l.inactive,
                        ].join(' · '),
                      ),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          for (final c in languageCodes)
                            Chip(
                              visualDensity: VisualDensity.compact,
                              label: Text(c.toUpperCase()),
                              backgroundColor:
                                  a.texts.any((t) => t.language == c)
                                  ? Theme.of(context)
                                        .colorScheme
                                        .primaryContainer
                                  : null,
                            ),
                        ],
                      ),
                      onTap: canWrite ? () => edit(a) : null,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AnswerEditor extends ConsumerStatefulWidget {
  const AnswerEditor({super.key, this.answer});
  final PreparedAnswer? answer;

  @override
  ConsumerState<AnswerEditor> createState() => _AnswerEditorState();
}

class _AnswerEditorState extends ConsumerState<AnswerEditor>
    with SingleTickerProviderStateMixin {
  late final a = widget.answer;
  late final _code = TextEditingController(text: a?.code);
  late final _name = TextEditingController(text: a?.name);
  late final _category = TextEditingController(text: a?.category);
  late bool _active = a?.active ?? true;
  late final Map<String, (TextEditingController, TextEditingController)>
  _texts = {
    for (final c in languageCodes)
      c: (
        TextEditingController(
          text: a?.texts.where((t) => t.language == c).firstOrNull?.subject,
        ),
        TextEditingController(
          text: a?.texts.where((t) => t.language == c).firstOrNull?.body,
        ),
      ),
  };
  late final _tabs = TabController(length: languageCodes.length, vsync: this);
  String? _error;

  void _insert(String placeholder) {
    final body = _texts[languageCodes[_tabs.index]]!.$2;
    final sel = body.selection;
    final text = '{{$placeholder}}';
    final start = sel.isValid ? sel.start : body.text.length;
    final end = sel.isValid ? sel.end : body.text.length;
    body.value = TextEditingValue(
      text: body.text.replaceRange(start, end, text),
      selection: TextSelection.collapsed(offset: start + text.length),
    );
  }

  Future<void> _save() async {
    final input = PreparedAnswerInput(
      code: _code.text.trim(),
      name: _name.text.trim(),
      category: _category.text.trim().isEmpty ? null : _category.text.trim(),
      active: _active,
      texts: [
        for (final c in languageCodes)
          if (_texts[c]!.$2.text.trim().isNotEmpty)
            AnswerText(
              language: c,
              subject: _texts[c]!.$1.text.trim(),
              body: _texts[c]!.$2.text,
            ),
      ],
    );
    try {
      final api = ref.read(apiProvider).helpdesk;
      if (a == null) {
        await api.createAnswer(body: input);
      } else {
        await api.updateAnswer(id: a!.id, body: input);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final placeholders =
        ref.watch(_placeholdersProvider).value ?? const <String>[];
    const gap = SizedBox(height: 12, width: 12);
    return AlertDialog(
      title: Text(a == null ? l.newAnswer : a!.name),
      content: SizedBox(
        width: 760,
        height: 600,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 180,
                  child: TextField(
                    controller: _code,
                    decoration: InputDecoration(labelText: l.code),
                  ),
                ),
                gap,
                Expanded(
                  child: TextField(
                    controller: _name,
                    decoration: InputDecoration(labelText: l.name),
                  ),
                ),
                gap,
                SizedBox(
                  width: 160,
                  child: TextField(
                    controller: _category,
                    decoration: InputDecoration(labelText: l.category),
                  ),
                ),
                Checkbox(
                  value: _active,
                  onChanged: (v) => setState(() => _active = v ?? true),
                ),
                Text(l.active),
              ],
            ),
            gap,
            TabBar(
              controller: _tabs,
              tabs: [for (final c in languageCodes) Tab(text: languageName(c))],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  for (final c in languageCodes)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Column(
                        children: [
                          TextField(
                            controller: _texts[c]!.$1,
                            decoration: InputDecoration(
                              labelText: l.subjectOptional,
                            ),
                          ),
                          gap,
                          Expanded(
                            child: TextField(
                              controller: _texts[c]!.$2,
                              expands: true,
                              maxLines: null,
                              textAlignVertical: TextAlignVertical.top,
                              decoration: InputDecoration(
                                labelText: l.text,
                                alignLabelWithHint: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            gap,
            Text(
              l.placeholdersHelp,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Wrap(
              spacing: 6,
              children: [
                for (final p in placeholders)
                  ActionChip(
                    label: Text('{{$p}}'),
                    onPressed: () => _insert(p),
                  ),
              ],
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(onPressed: _save, child: Text(l.save)),
      ],
    );
  }
}

final _placeholdersProvider = FutureProvider<List<String>>(
  (ref) => ref.watch(apiProvider).helpdesk.placeholders(),
);
