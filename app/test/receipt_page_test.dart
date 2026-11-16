import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konsum/main.dart';
import 'package:konsum/services/receipt_image.dart';
import 'package:konsum/services/receipt_ocr.dart';
import 'package:konsum/state/app_state.dart';
import 'package:konsum/storage/store.dart';
import 'package:konsum/ui/receipt_page.dart';
import 'package:konsum_core/konsum_core.dart';

/// Liefert für jeden Lauf denselben (erfundenen) Bontext.
class _FakeOcr implements OcrEngine {
  _FakeOcr(this.text);
  final String text;
  int calls = 0;

  @override
  int get parallel => 2;

  @override
  Future<String> recognize(GrayImage image, {required int psm}) async {
    calls++;
    return text;
  }
}

const _bon = '''
Frischmarkt
Hauptstr. 1
BIO VOLLMILCH 1L        2,58 € B
  (2 x 1,29 €/ST)
OA ORIGINAL SCHEIB      3,49 € B
PFAND                   0,25 € A
Summe                   6,32 €
''';

Future<Uint8List> _photo() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 60, 120),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  final image = await recorder.endRecording().toImage(60, 120);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  return png!.buffer.asUint8List();
}

void main() {
  testWidgets('Bon lesen, zuordnen, Preise übernehmen', (tester) async {
    final state = (await tester.runAsync(
      () => AppState.load(MemoryStore(), random: math.Random(1)),
    ))!;
    final session = state.currentGroup!;
    final group = session.group;
    final milk = group.createArticle('Milch');
    final cheese = group.createArticle('old Amsterdam');
    final shop = group.createShop('Frischmarkt');
    session
      ..apply(milk.changes)
      ..apply(cheese.changes)
      ..apply(shop.changes);
    final photo = (await tester.runAsync(_photo))!;
    final ocr = _FakeOcr(_bon);

    await tester.pumpWidget(KonsumApp(state: state));
    tester
        .state<NavigatorState>(find.byType(Navigator).first)
        .push(
          MaterialPageRoute<void>(
            builder: (_) =>
                ReceiptPage(session: session, engine: ocr, photo: photo),
          ),
        );
    // Lesen läuft in Isolates: echte Zeit vergehen lassen.
    for (var i = 0; i < 600 && find.text('PFAND').evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    expect(ocr.calls, ocrVariants.length);
    expect(find.textContaining('stimmt mit dem Bon überein'), findsOneWidget);
    // Laden aus dem Bonkopf erkannt.
    expect(find.text('Frischmarkt'), findsWidgets);
    expect(find.text('→ Milch'), findsOneWidget);
    expect(find.text('→ Artikel wählen …'), findsNWidgets(2));

    // Käse von Hand zuordnen, Pfand immer ignorieren.
    await tester.tap(find.text('OA ORIGINAL SCHEIB'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'old Amsterdam'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PFAND'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Immer ignorieren'));
    await tester.pumpAndSettle();
    expect(find.text('→ wird ignoriert'), findsOneWidget);

    await tester.tap(find.text('2 übernehmen'));
    await tester.pumpAndSettle();
    expect(group.lastPrice(milk.id)!.cents, 258);
    expect(group.lastPrice(milk.id)!.quantity, 2);
    expect(group.lastPrice(cheese.id)!.shopId, shop.id);
    expect(find.text('2 Preise übernommen'), findsOneWidget);

    // Beim nächsten Bon sind die Zuordnungen gelernt.
    final m = ReceiptMatcher(group, shopId: shop.id);
    expect(
      m.match(ReceiptLine(text: 'OA ORIGINAL SCHEIB', cents: 349)).articleId,
      cheese.id,
    );
    expect(m.match(ReceiptLine(text: 'PFAND', cents: 25)).ignore, isTrue);
    await tester.pump(const Duration(seconds: 5));
  });
}
