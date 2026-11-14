import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/helpdesk/ticket_screen.dart';
import 'package:tradocraft_app/features/kb/kb_entry_screen.dart';
import 'package:tradocraft_app/features/kb/kb_page.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';
import 'package:tradocraft_app/portal/portal_help.dart';
import 'package:tradocraft_app/portal/portal_pages.dart';
import 'package:tradocraft_app/portal/portal_state.dart';
import 'package:tradocraft_app/shared/markdown_view.dart';
import 'package:tradocraft_app/shared/photos.dart';

import 'fake_http.dart';

const _kbPerms = [
  'kb.read',
  'kb.write',
  'helpdesk.read',
  'helpdesk.write',
  'helpdesk.reply',
];

Map<String, Object?> _text(String lang, String title, String body) => {
  'language': lang,
  'title': title,
  'summary': '',
  'body': body,
};

Map<String, Object?> _entry({
  String status = 'draft',
  String visibility = 'portal',
  List<Map<String, Object?>>? texts,
  int version = 0,
  List<Map<String, Object?>> images = const [],
}) => {
  'id': 'e1',
  'number': 'KB-00001',
  'slug': 'reset-the-pump',
  'category_id': null,
  'visibility': visibility,
  'status': status,
  'author_id': 'u1',
  'author_name': 'Support Agent',
  'published_at': null,
  'created_at': '2026-11-10T09:00:00Z',
  'updated_at': '2026-11-10T09:00:00Z',
  'view_count': 7,
  'helpful_yes': 3,
  'helpful_no': 1,
  'version': version,
  'texts':
      texts ??
      [_text('en', 'Reset the pump', 'Hold the **button** for five seconds.')],
  'tags': ['pump'],
  'related': <Object?>[],
  'product_ids': <String>[],
  'ticket_categories': <String>[],
  'images': images,
};

Map<String, Object?> _version(int v, String body, {int? restoredFrom}) => {
  'version': v,
  'editor_id': 'u1',
  'editor_name': 'Support Agent',
  'edited_at': '2026-11-10T10:0$v:00Z',
  'restored_from': restoredFrom,
  'texts': [_text('en', 'Reset the pump', body)],
};

Map<String, Object?> _summary(
  String id,
  String title, {
  String status = 'published',
  String visibility = 'portal',
  String snippet = '',
}) => {
  'id': id,
  'number': 'KB-$id',
  'slug': title.toLowerCase().replaceAll(' ', '-'),
  'category_id': null,
  'visibility': visibility,
  'status': status,
  'language': 'en',
  'fallback': false,
  'title': title,
  'snippet': snippet,
  'tags': <String>[],
  'updated_at': '2026-11-10T09:00:00Z',
  'published_at': '2026-11-10T09:00:00Z',
  'view_count': 0,
  'helpful_yes': 0,
  'helpful_no': 0,
  'score': null,
};

Map<String, Object?> _reader(String id, String title, {String? lang}) => {
  'id': id,
  'number': 'KB-1',
  'slug': 'x',
  'category_id': null,
  'language': lang ?? 'en',
  'fallback': false,
  'available_languages': ['en'],
  'title': title,
  'summary': '',
  'body': '# Steps\n\n1. Press the **button**\n2. Wait\n\nSee [the manual](https://x.example/m).',
  'tags': <String>[],
  'related': [
    {'id': 'a2', 'number': 'KB-2', 'title': 'Other article'},
  ],
  'images': <Object?>[],
  'updated_at': '2026-11-10T09:00:00Z',
  'my_vote': null,
};

Map<String, Object?> _readerSummary(
  String id,
  String title, {
  String snippet = '',
}) => {
  'id': id,
  'number': 'KB-$id',
  'slug': 'x',
  'category_id': null,
  'language': 'en',
  'fallback': false,
  'title': title,
  'snippet': snippet,
  'tags': <String>[],
  'updated_at': '2026-11-10T09:00:00Z',
};

Future<void> _pumpStaff(WidgetTester tester, FakeHttp http, Widget home) async {
  tester.view.physicalSize = const Size(1700, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(fakeDio(http))],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: home),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpPortal(
  WidgetTester tester,
  FakeHttp http,
  Widget home,
) async {
  tester.view.physicalSize = const Size(1000, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        portalDioProvider.overrideWithValue(fakeDio(http)),
        initialPortalTokenProvider.overrideWithValue('tcs_x'),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: home),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('markdown', () {
    test('inline styles, links and pictures', () {
      expect(
        parseInline('a **b** *c* `d` [e](https://x.example) ![p](image:42)'),
        [
          const MdSpan('a '),
          const MdSpan('b', bold: true),
          const MdSpan(' '),
          const MdSpan('c', italic: true),
          const MdSpan(' '),
          const MdSpan('d', code: true),
          const MdSpan(' '),
          const MdSpan('e', url: 'https://x.example'),
          const MdSpan(' '),
          const MdSpan('p', image: '42'),
        ],
      );
      expect(parseInline('snake_case_name'), [const MdSpan('snake_case_name')]);
      expect(parseInline(r'not \*bold\*'), [const MdSpan('not *bold*')]);
    });

    test('links are only live for web and mail addresses', () {
      expect(isSafeLink('https://a.example'), isTrue);
      expect(isSafeLink('mailto:a@b.example'), isTrue);
      expect(isSafeLink('javascript:alert(1)'), isFalse);
      expect(isSafeLink('file:///etc/passwd'), isFalse);
      final unsafe = parseInline('[x](javascript:alert(1))');
      expect(unsafe.every((s) => s.url == null), isTrue);
      // A remote picture is not loaded; only its description is shown.
      final remote = parseInline('![logo](https://evil.example/t.png)');
      expect(remote.single.image, isNull);
    });

    test('blocks', () {
      final b = parseBlocks(
        '# T\n\npara one\nline two\n\n- a\n- b\n\n1. x\n2. y\n\n> q\n\n```\ncode\n```\n\n---',
      );
      expect(b.map((e) => e.runtimeType).toList(), [
        MdHeading,
        MdParagraph,
        MdList,
        MdList,
        MdQuote,
        MdCode,
        MdRule,
      ]);
      expect((b[1] as MdParagraph).text, 'para one line two');
      expect((b[2] as MdList).ordered, isFalse);
      expect((b[3] as MdList).items, ['x', 'y']);
    });

    test('snippets highlight the matched words', () {
      final spans = snippetSpans('the \u{E000}pump\u{E001} leaks', null);
      expect(spans.map((s) => s.text).toList(), ['the ', 'pump', ' leaks']);
      expect(spans[1].style?.fontWeight, FontWeight.bold);
      expect(stripMarks('a \u{E000}b\u{E001}'), 'a b');
    });

    testWidgets('renders text and never interprets HTML', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MarkdownView(
              source: '# Title\n\nHello <b>raw</b> <script>x</script> **bold**\n\n- one\n- two',
            ),
          ),
        ),
      );
      expect(find.text('Title', findRichText: true), findsOneWidget);
      expect(
        find.textContaining(
          '<b>raw</b> <script>x</script>',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(find.text('one', findRichText: true), findsOneWidget);
    });

    testWidgets('a link opens through the callback; pictures use the builder', (
      tester,
    ) async {
      String? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarkdownView(
              source: 'See [the manual](https://x.example/m) ![fig](image:7)',
              onOpenLink: (u) async => opened = u,
              imageBuilder: (_, id, alt) => Text('IMG $id $alt'),
            ),
          ),
        ),
      );
      expect(find.text('IMG 7 fig'), findsOneWidget);
      final rich = tester.widget<RichText>(
        find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText().contains('the manual'),
        ),
      );
      TextSpan? link;
      rich.text.visitChildren((s) {
        if (s is TextSpan && s.text == 'the manual') link = s;
        return true;
      });
      (link!.recognizer! as TapGestureRecognizer).onTap!();
      expect(opened, 'https://x.example/m');
    });
  });

  group('staff', () {
    testWidgets('the list searches and filters', (tester) async {
      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(_kbPerms),
        'GET /api/v1/kb/categories': (_) => [],
        'GET /api/v1/kb/entries': (_) => [
          _summary(
            'e1',
            'Reset the pump',
            snippet: 'hold the \u{E000}button\u{E001}',
            visibility: 'internal',
          ),
        ],
      });
      await _pumpStaff(tester, http, const KbPage());
      expect(find.text('Reset the pump'), findsOneWidget);
      expect(find.text('Internal (staff only)'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'pump');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(http.queries.last['q'], 'pump');

      await tester.tap(find.byKey(const ValueKey('filter-status')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Published').last);
      await tester.pumpAndSettle();
      expect(http.queries.last['status'], 'published');
      expect(http.queries.last['q'], 'pump', reason: 'filters combine');

      await tester.tap(find.byKey(const ValueKey('filter-language')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nederlands').last);
      await tester.pumpAndSettle();
      expect(http.queries.last['language'], 'nl');
    });

    testWidgets('the editor edits per language, previews, saves and restores', (
      tester,
    ) async {
      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson([..._kbPerms, 'kb.admin']),
        'GET /api/v1/kb/categories': (_) => [],
        'GET /api/v1/kb/entries/e1': (_) =>
            _entry(status: 'published', version: 2),
        'GET /api/v1/kb/entries/e1/versions': (_) => [
          _version(2, 'Hold for ten seconds.'),
          _version(1, 'Hold the button for five seconds.'),
        ],
        'PUT /api/v1/kb/entries/e1': (_) =>
            _entry(status: 'published', version: 3),
        'POST /api/v1/kb/entries/e1/versions/1/restore': (_) =>
            _entry(status: 'published', version: 3),
        'POST /api/v1/kb/entries/e1/unpublish': (_) => _entry(),
      });
      await _pumpStaff(tester, http, const KbEntryScreen(id: 'e1'));
      expect(find.text('KB-00001 · v2'), findsOneWidget);
      expect(find.text('Published'), findsWidgets);
      final title = find.byKey(const ValueKey('title-en'));
      expect(
        tester.widget<TextField>(title).controller!.text,
        'Reset the pump',
      );

      // Preview renders the Markdown.
      await tester.tap(find.text('Preview'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'Hold the button for five seconds.',
          findRichText: true,
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Write'));
      await tester.pumpAndSettle();

      // Edit English, add Dutch.
      await tester.enterText(title, 'Reset the pump unit');
      await tester.tap(find.text('Nederlands'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('title-nl')),
        'Pomp resetten',
      );
      await tester.enterText(
        find.byKey(const ValueKey('body-nl')),
        'Houd de knop ingedrukt.',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final sent = http.bodies['PUT /api/v1/kb/entries/e1']! as Map;
      expect(sent['visibility'], 'portal');
      expect(sent['tags'], ['pump']);
      final texts = (sent['texts'] as List).cast<Map>();
      expect(texts.map((t) => t['language']).toList(), ['nl', 'en']);
      expect(texts.last['title'], 'Reset the pump unit');
      expect(texts.first['body'], 'Houd de knop ingedrukt.');

      // Version history and restore.
      await tester.ensureVisible(find.byKey(const ValueKey('history')));
      await tester.tap(find.byKey(const ValueKey('history')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('restore-1')));
      await tester.pumpAndSettle();
      expect(
        http.requests,
        contains('POST /api/v1/kb/entries/e1/versions/1/restore'),
      );

      // Publishing actions are for people with kb.admin.
      expect(find.text('Unpublish'), findsOneWidget);
      await tester.tap(find.text('Unpublish'));
      await tester.pumpAndSettle();
      expect(http.requests, contains('POST /api/v1/kb/entries/e1/unpublish'));
      expect(find.text('Publish'), findsOneWidget);
    });

    testWidgets('without kb.admin there are no publishing buttons', (
      tester,
    ) async {
      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(_kbPerms),
        'GET /api/v1/kb/categories': (_) => [],
        'GET /api/v1/kb/entries/e1': (_) => _entry(),
        'GET /api/v1/kb/entries/e1/versions': (_) => [],
      });
      await _pumpStaff(tester, http, const KbEntryScreen(id: 'e1'));
      expect(find.text('Publish'), findsNothing);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('a new article is created as a draft', (tester) async {
      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(_kbPerms),
        'GET /api/v1/kb/categories': (_) => [],
        'POST /api/v1/kb/entries': (_) => _entry(),
      });
      await _pumpStaff(tester, http, const KbEntryScreen(id: 'new'));
      await tester.enterText(
        find.byKey(const ValueKey('title-en')),
        'Reset the pump',
      );
      await tester.enterText(
        find.byKey(const ValueKey('body-en')),
        'Hold the button.',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final sent = http.bodies['POST /api/v1/kb/entries']! as Map;
      expect(sent['visibility'], 'internal');
      expect((sent['texts'] as List).single['title'], 'Reset the pump');
      expect(find.text('KB-00001 · v0'), findsOneWidget);
    });

    testWidgets('images are uploaded and inserted into the text', (
      tester,
    ) async {
      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(_kbPerms),
        'GET /api/v1/kb/categories': (_) => [],
        'GET /api/v1/kb/entries/e1': (_) => _entry(
          images: [
            {
              'id': 'f1',
              'filename': 'part.png',
              'content_type': 'image/png',
              'size_bytes': 2048,
              'uploader_name': 'Support Agent',
              'created_at': '2026-11-10T09:00:00Z',
            },
          ],
        ),
        'GET /api/v1/kb/entries/e1/versions': (_) => [],
        'POST /api/v1/kb/entries/e1/images': (_) => {},
        'GET /api/v1/kb/entries/e1/images/f1': (_) => fakeJpeg,
      });
      await _pumpStaff(
        tester,
        http,
        KbEntryScreen(
          id: 'e1',
          pickImages: (_) async => [
            PickedPhoto(Uint8List.fromList([1, 2, 3]), 'new.png'),
          ],
        ),
      );
      await tester.ensureVisible(find.text('Upload image'));
      await tester.tap(find.text('Upload image'));
      await tester.pumpAndSettle();
      expect(http.requests, contains('POST /api/v1/kb/entries/e1/images'));
      await tester.ensureVisible(find.byKey(const ValueKey('insert-f1')));
      await tester.tap(find.byKey(const ValueKey('insert-f1')));
      await tester.pumpAndSettle();
      final body = tester.widget<TextField>(
        find.byKey(const ValueKey('body-en')),
      );
      expect(body.controller!.text, contains('![part.png](image:f1)'));
    });

    testWidgets('the ticket suggests articles and inserts text or a link', (
      tester,
    ) async {
      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(_kbPerms),
        'GET /api/v1/users': (_) => [],
        'GET /api/v1/helpdesk/teams': (_) => [],
        'GET /api/v1/tickets/t1': (_) => {
          'ticket': {
            'id': 't1',
            'number': 'T2026-00007',
            'subject': 'Pump is noisy',
            'status': 'open',
            'priority': 'normal',
            'category': 'service',
            'language': 'en',
            'customer_id': 'c1',
            'customer_name': 'Alpha NV',
            'contact_name': 'Anna',
            'contact_email': 'anna@alpha.example',
            'internal': false,
            'article_count': 0,
            'created_at': '2026-11-09T09:00:00Z',
            'updated_at': '2026-11-09T09:00:00Z',
            ...ticketExtras(),
          },
          ...detailExtras(),
          'articles': <Object?>[],
        },
        'GET /api/v1/quotations': (_) => {'items': [], 'total': 0},
        'GET /api/v1/opportunities': (_) => {'items': [], 'total': 0},
        'GET /api/v1/customers/c1/contacts': (_) => [],
        'GET /api/v1/tickets/t1/repairs': (_) => [],
        'GET /api/v1/tickets/t1/time-entries': (_) => {
          'items': <Object?>[],
          'total_minutes': 0,
          'billable_minutes': 0,
        },
        'GET /api/v1/tickets/t1/kb-suggestions': (_) => [
          _summary(
            'e1',
            'Reset the pump',
            snippet: 'hold the \u{E000}button\u{E001}',
          ),
          _summary('e2', 'Staff checklist', visibility: 'internal'),
        ],
        'GET /api/v1/tickets/t1/kb-entries/e1/render': (_) => {
          'entry_id': 'e1',
          'language': 'en',
          'fallback': false,
          'title': 'Reset the pump',
          'summary': '',
          'text': 'Hold the button for five seconds.',
          'link': 'http://portal.example/help/e1',
        },
        'GET /api/v1/tickets/t1/kb-entries/e2/render': (_) => {
          'entry_id': 'e2',
          'language': 'en',
          'fallback': false,
          'title': 'Staff checklist',
          'summary': '',
          'text': 'Check the fuse.',
          'link': null,
        },
        'GET /api/v1/kb/entries': (_) => [_summary('e1', 'Reset the pump')],
      });
      await _pumpStaff(tester, http, const TicketScreen(id: 't1'));
      expect(find.text('Suggested articles'), findsOneWidget);
      expect(find.text('KB-e1 · Reset the pump'), findsOneWidget);

      final composer = find.widgetWithText(TextField, 'Message');
      await tester.ensureVisible(find.byKey(const ValueKey('insert-text-e1')));
      await tester.tap(find.byKey(const ValueKey('insert-text-e1')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(composer).controller!.text,
        'Reset the pump\n\nHold the button for five seconds.\n\nhttp://portal.example/help/e1',
      );

      await tester.ensureVisible(find.byKey(const ValueKey('insert-link-e1')));
      await tester.tap(find.byKey(const ValueKey('insert-link-e1')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(composer).controller!.text,
        endsWith('\n\nReset the pump: http://portal.example/help/e1'),
      );

      // An internal article has no link to send a customer.
      await tester.ensureVisible(find.byKey(const ValueKey('insert-link-e2')));
      await tester.tap(find.byKey(const ValueKey('insert-link-e2')));
      await tester.pumpAndSettle();
      expect(
        find.text('This article is internal: only its text can be inserted.'),
        findsOneWidget,
      );

      // The picker finds any published article.
      await tester.ensureVisible(find.byKey(const ValueKey('insert-article')));
      await tester.tap(find.byKey(const ValueKey('insert-article')));
      await tester.pumpAndSettle();
      expect(http.queries.last['status'], 'published');
      expect(http.queries.last['language'], 'en');
      await tester.tap(find.byKey(const ValueKey('pick-e1')));
      await tester.pumpAndSettle();
      expect(
        '\n\n'
            .allMatches(tester.widget<TextField>(composer).controller!.text)
            .length,
        greaterThan(3),
      );
    });

    testWidgets('without kb.read the ticket has no suggestions', (
      tester,
    ) async {
      final http = FakeHttp({
        'GET /api/v1/me': (_) =>
            meJson(['helpdesk.read', 'helpdesk.write', 'helpdesk.reply']),
        'GET /api/v1/users': (_) => [],
        'GET /api/v1/helpdesk/teams': (_) => [],
        'GET /api/v1/tickets/t1': (_) => {
          'ticket': {
            'id': 't1',
            'number': 'T1',
            'subject': 'Pump',
            'status': 'open',
            'priority': 'normal',
            'category': 'service',
            'language': 'en',
            'customer_id': 'c1',
            'customer_name': 'Alpha NV',
            'contact_name': 'Anna',
            'contact_email': 'anna@alpha.example',
            'internal': false,
            'article_count': 0,
            'created_at': '2026-11-09T09:00:00Z',
            'updated_at': '2026-11-09T09:00:00Z',
            ...ticketExtras(),
          },
          ...detailExtras(),
          'articles': <Object?>[],
        },
        'GET /api/v1/quotations': (_) => {'items': [], 'total': 0},
        'GET /api/v1/opportunities': (_) => {'items': [], 'total': 0},
        'GET /api/v1/customers/c1/contacts': (_) => [],
        'GET /api/v1/tickets/t1/repairs': (_) => [],
        'GET /api/v1/tickets/t1/time-entries': (_) => {
          'items': <Object?>[],
          'total_minutes': 0,
          'billable_minutes': 0,
        },
      });
      await _pumpStaff(tester, http, const TicketScreen(id: 't1'));
      expect(find.text('Suggested articles'), findsNothing);
      expect(http.requests.where((r) => r.contains('kb-')), isEmpty);
    });
  });

  group('portal', () {
    testWidgets('browse by category, search and open the list', (tester) async {
      final http = FakeHttp({
        'GET /api/v1/portal/kb/categories': (_) => [
          {
            'id': 'k1',
            'parent_id': null,
            'name': 'Pumps',
            'sort_order': 0,
            'entry_count': 2,
          },
          {
            'id': 'k2',
            'parent_id': 'k1',
            'name': 'Seals',
            'sort_order': 0,
            'entry_count': 1,
          },
        ],
        'GET /api/v1/portal/kb/entries': (_) => [
          _readerSummary(
            'a1',
            'Reset the pump',
            snippet: 'hold the \u{E000}button\u{E001}',
          ),
        ],
      });
      await _pumpPortal(tester, http, const PortalHelpPage());
      expect(find.text('How can we help?'), findsOneWidget);
      expect(find.text('Reset the pump'), findsOneWidget);
      expect(http.queries.last['language'], 'en');

      await tester.enterText(
        find.byKey(const ValueKey('help-search')),
        'button',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(http.queries.last['q'], 'button');

      await tester.tap(find.byKey(const ValueKey('category-k1')));
      await tester.pumpAndSettle();
      expect(http.queries.last['category_id'], 'k1');
      expect(http.queries.last['q'], 'button');
      // The sub-categories of the chosen category appear.
      expect(find.text('Seals (1)'), findsOneWidget);
    });

    testWidgets('an empty search offers to open a ticket', (tester) async {
      final http = FakeHttp({
        'GET /api/v1/portal/kb/categories': (_) => [],
        'GET /api/v1/portal/kb/entries': (_) => [],
      });
      await _pumpPortal(tester, http, const PortalHelpPage());
      expect(find.textContaining('No articles found'), findsOneWidget);
    });

    testWidgets('reading an article and voting, changing the vote', (
      tester,
    ) async {
      final http = FakeHttp({
        'GET /api/v1/portal/kb/entries/a1': (_) =>
            _reader('a1', 'Reset the pump'),
        'PUT /api/v1/portal/kb/entries/a1/vote': (_) => null,
      });
      await _pumpPortal(tester, http, const PortalHelpArticlePage(id: 'a1'));
      expect(find.byKey(const ValueKey('article-title')), findsOneWidget);
      expect(find.text('Steps', findRichText: true), findsOneWidget);
      expect(find.text('Press the button', findRichText: true), findsOneWidget);
      expect(find.text('Other article'), findsOneWidget);
      expect(find.text('Thank you for your feedback.'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('vote-yes')));
      await tester.pumpAndSettle();
      expect(http.bodies['PUT /api/v1/portal/kb/entries/a1/vote'], {
        'helpful': true,
      });
      expect(find.text('Thank you for your feedback.'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('vote-no')));
      await tester.pumpAndSettle();
      expect(http.bodies['PUT /api/v1/portal/kb/entries/a1/vote'], {
        'helpful': false,
      });
      expect(find.text('Still need help? Open a ticket.'), findsOneWidget);
    });

    testWidgets(
      'the new ticket form suggests up to three articles while typing',
      (tester) async {
        final http = FakeHttp({
          'GET /api/v1/portal/kb/suggestions': (_) => [
            _readerSummary('a1', 'Reset the pump'),
            _readerSummary('a2', 'Pump is noisy'),
            _readerSummary('a3', 'Replace a seal'),
          ],
        });
        await _pumpPortal(tester, http, const PortalNewTicketPage());
        final subject = find.widgetWithText(TextField, 'Subject');
        // Too short: no request.
        await tester.enterText(subject, 'pu');
        await tester.pump(const Duration(milliseconds: 600));
        expect(http.requests, isEmpty);
        expect(find.byKey(const ValueKey('kb-deflection')), findsNothing);

        await tester.enterText(subject, 'pump leaks');
        await tester.pump(const Duration(milliseconds: 100));
        expect(http.requests, isEmpty, reason: 'debounced');
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
        expect(http.queries.last['q'], 'pump leaks');
        expect(http.queries.last['language'], 'en');
        expect(
          find.text('These articles may already answer your question'),
          findsOneWidget,
        );
        expect(find.text('Reset the pump'), findsOneWidget);
        expect(find.text('Replace a seal'), findsOneWidget);
        // The form itself is untouched.
        expect(find.text('Send'), findsOneWidget);
      },
    );

    testWidgets('a failing suggestion lookup never gets in the way', (
      tester,
    ) async {
      final http = FakeHttp({});
      await _pumpPortal(tester, http, const PortalNewTicketPage());
      await tester.enterText(
        find.widgetWithText(TextField, 'Subject'),
        'pump leaks',
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(http.requests, contains('GET /api/v1/portal/kb/suggestions'));
      expect(find.byKey(const ValueKey('kb-deflection')), findsNothing);
      expect(find.text('Send'), findsOneWidget);
      expect(find.textContaining('404'), findsNothing);
    });
  });
}
