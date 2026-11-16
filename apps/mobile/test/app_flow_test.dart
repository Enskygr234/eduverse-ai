import 'dart:io';

import 'package:eduverse_ai/app/app.dart';
import 'package:eduverse_ai/app/providers.dart';
import 'package:eduverse_ai/data/local/local_backend.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final pack = File('assets/content/courses.json').readAsStringSync();

  Widget app() => ProviderScope(
        overrides: [
          backendProvider.overrideWithValue(LocalBackend(store: MemoryStore(), loadContent: () async => pack)),
        ],
        child: const EduverseApp(),
      );

  testWidgets('register → onboarding → home → course → lesson intro', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('EduVerse AI'), findsOneWidget);

    await tester.tap(find.text('Hemen başla'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Adın'), 'Ece');
    await tester.enterText(find.widgetWithText(TextFormField, 'E-posta'), 'ece@example.com');
    await tester.enterText(find.widgetWithText(TextFormField, 'Şifre'), 'Sifre1234');
    await tester.tap(find.text('Hesap oluştur'));
    await tester.pumpAndSettle();

    // Onboarding: interests → goal → level → daily goal.
    expect(find.text('Neler öğrenmek istersin?'), findsOneWidget);
    await tester.tap(find.text('Diller'));
    await tester.pump();
    await tester.tap(find.text('Devam'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Seyahat'));
    await tester.pump();
    await tester.tap(find.text('Devam'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yeni başlıyorum'));
    await tester.pump();
    await tester.tap(find.text('Devam'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Planımı oluştur'));
    await tester.pumpAndSettle();

    // Home dashboard.
    expect(find.textContaining('Ece!'), findsOneWidget);
    expect(find.text('Kaldığın yerden devam et'), findsOneWidget);
    expect(find.text('Merhaba!'), findsOneWidget);

    await tester.tap(find.text('Derse başla'));
    await tester.pumpAndSettle();
    expect(find.textContaining('soruya başla'), findsOneWidget);

    await tester.tap(find.textContaining('soruya başla'));
    await tester.pumpAndSettle();
    expect(find.text('Soru 1/4'), findsOneWidget);
    expect(find.text('Kontrol et'), findsOneWidget);
  });
}
