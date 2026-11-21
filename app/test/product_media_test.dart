import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/products/media_tab.dart';
import 'package:tradocraft_app/features/products/product_form.dart';
import 'package:tradocraft_app/features/products/product_thumb.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';
import 'package:tradocraft_app/shared/app_icons.dart';
import 'package:tradocraft_app/shared/photos.dart';

import 'fake_http.dart';

// 1x1 transparent PNG
final _png = Uint8List.fromList([
  0x89,
  0x50,
  0x4e,
  0x47,
  0x0d,
  0x0a,
  0x1a,
  0x0a,
  0x00,
  0x00,
  0x00,
  0x0d,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x02,
  0x00,
  0x00,
  0x00,
  0x90,
  0x77,
  0x53,
  0xde,
  0x00,
  0x00,
  0x00,
  0x0c,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9c,
  0x63,
  0xf8,
  0xcf,
  0xc0,
  0x00,
  0x00,
  0x03,
  0x01,
  0x01,
  0x00,
  0xc9,
  0xfe,
  0x92,
  0xef,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4e,
  0x44,
  0xae,
  0x42,
  0x60,
  0x82,
]);

final _mp4 = Uint8List.fromList([0, 0, 0, 0x18, ...'ftypmp42'.codeUnits]);

Map<String, Object?> _productJson({
  String? defaultMediaId,
  String? defaultMediaKind,
}) => {
  'id': 'p1',
  'code': 'PUMP-05',
  'name': 'Pump',
  'description': '',
  'unit': 'pcs',
  'product_type': 'purchased',
  'tracking': 'none',
  'non_discountable': false,
  'price_on_request': false,
  'price_is_indicative': false,
  'vat_rate': '21',
  'active': true,
  'default_media_id': ?defaultMediaId,
  'default_media_kind': ?defaultMediaKind,
};

Future<void> _pump(WidgetTester tester, FakeHttp http, Widget child) async {
  tester.view.physicalSize = const Size(1400, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(fakeDio(http))],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'creating a product can attach pictures and videos and choose the default',
    (tester) async {
      var uploadCount = 0;
      String? defaultMediaId;
      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(['products.read', 'products.write']),
        'GET /api/v1/product-families': (_) => <Object?>[],
        'GET /api/v1/packaging-categories': (_) => <Object?>[],
        'GET /api/v1/vat-rates': (_) => <Object?>[],
        'POST /api/v1/products': (_) => _productJson(),
        'POST /api/v1/products/p1/media': (_) {
          uploadCount += 1;
          final id = 'm$uploadCount';
          defaultMediaId ??= id;
          return {
            'id': id,
            'kind': uploadCount == 1 ? 'video' : 'image',
            'content_type': uploadCount == 1 ? 'video/mp4' : 'image/png',
            'filename': uploadCount == 1 ? 'demo.mp4' : 'front.png',
            'size_bytes': 64,
            'caption': '',
            'is_default': uploadCount == 1,
            'created_at': '2026-11-21T00:00:00Z',
          };
        },
        'PATCH /api/v1/products/p1/media/m2': (body) {
          defaultMediaId = 'm2';
          return {
            'id': 'm2',
            'kind': 'image',
            'content_type': 'image/png',
            'filename': 'front.png',
            'size_bytes': 64,
            'caption': '',
            'is_default': true,
            'created_at': '2026-11-21T00:00:00Z',
          };
        },
        'GET /api/v1/products/p1': (_) => _productJson(
          defaultMediaId: defaultMediaId,
          defaultMediaKind: 'image',
        ),
      });

      await _pump(
        tester,
        http,
        Builder(
          builder: (context) => FilledButton(
            onPressed: () => showProductForm(
              context,
              pickMedia: (_) async => [
                PickedPhoto(_mp4, 'demo.mp4'),
                PickedPhoto(_png, 'front.png'),
                PickedPhoto(_png, 'side.png'),
              ],
            ),
            child: const Text('New'),
          ),
        ),
      );

      await tester.tap(find.text('New'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Code'), 'PUMP-05');
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Pump');

      await tester.tap(find.byKey(const ValueKey('product-form-add-media')));
      await tester.pumpAndSettle();

      // First staged item starts as default; second item has a "Make default" button.
      expect(
        find.byKey(const ValueKey('staged-media-default-0')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('staged-media-make-default-1')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('staged-media-default-1')),
        findsOneWidget,
      );

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(
        http.requests,
        containsAllInOrder([
          'POST /api/v1/products',
          'POST /api/v1/products/p1/media',
          'POST /api/v1/products/p1/media',
          'POST /api/v1/products/p1/media',
          'PATCH /api/v1/products/p1/media/m2',
          'GET /api/v1/products/p1',
        ]),
      );
      expect(http.bodies['PATCH /api/v1/products/p1/media/m2'], {
        'is_default': true,
      });
    },
  );

  testWidgets('MediaTab shows default first and can switch default or delete', (
    tester,
  ) async {
    final items = <Map<String, Object?>>[
      {
        'id': 'm1',
        'kind': 'image',
        'content_type': 'image/png',
        'filename': 'a.png',
        'size_bytes': 64,
        'caption': 'Front',
        'is_default': true,
        'created_at': '2026-11-21T00:00:00Z',
      },
      {
        'id': 'm2',
        'kind': 'video',
        'content_type': 'video/mp4',
        'filename': 'demo.mp4',
        'size_bytes': 64,
        'caption': '',
        'is_default': false,
        'created_at': '2026-11-21T00:01:00Z',
      },
    ];
    final http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(['products.read', 'products.write']),
      'GET /api/v1/products/p1/media': (_) => items,
      'GET /api/v1/products/p1/media/m1': (_) => _png,
      'PATCH /api/v1/products/p1/media/m2': (_) {
        items[0]['is_default'] = false;
        items[1]['is_default'] = true;
        return items[1];
      },
      'DELETE /api/v1/products/p1/media/m1': (_) {
        items.removeWhere((e) => e['id'] == 'm1');
        return null;
      },
    });

    await _pump(
      tester,
      http,
      Consumer(
        builder: (context, ref, _) {
          ref.watch(meProvider);
          return const MediaTab(productId: 'p1');
        },
      ),
    );

    expect(find.byKey(const ValueKey('media-m1')), findsOneWidget);
    expect(find.byKey(const ValueKey('media-m2')), findsOneWidget);
    expect(find.byKey(const ValueKey('media-default-badge')), findsOneWidget);

    await tester.tap(find.text('Make default'));
    await tester.pumpAndSettle();
    expect(http.requests, contains('PATCH /api/v1/products/p1/media/m2'));

    await tester.tap(find.byIcon(AppIcons.delete).first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('media-m1')), findsNothing);
  });

  testWidgets('ProductThumb renders image or video/empty placeholder', (
    tester,
  ) async {
    final http = FakeHttp({'GET /api/v1/products/p1/media/m1': (_) => _png});
    await _pump(
      tester,
      http,
      const Row(
        children: [
          ProductThumb(productId: 'p1', mediaId: 'm1'),
          ProductThumb(productId: 'p2', mediaId: 'm2', isVideo: true),
          ProductThumb(productId: 'p3', mediaId: null),
        ],
      ),
    );

    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(AppIcons.playCircle), findsOneWidget);
    expect(find.byIcon(AppIcons.photo), findsOneWidget);
  });
}
