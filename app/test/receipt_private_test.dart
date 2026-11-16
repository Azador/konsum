// Läuft nur mit privaten Testdaten (test-privat/bons/*.jpg, nicht im Repo)
// und installiertem Tesseract: ganze Kette vom Foto bis zum Bon.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:konsum/services/receipt_ocr.dart';

void main() {
  final dir = Directory('../test-privat/bons');
  if (!dir.existsSync()) return;
  final photos = dir.listSync().whereType<File>().where(
    (f) => f.path.toLowerCase().endsWith('.jpg'),
  );
  for (final f in photos) {
    testWidgets('Foto ${f.path.split('/').last}', (tester) async {
      await tester.runAsync(() async {
        final sw = Stopwatch()..start();
        final r = await readReceiptPhoto(f.readAsBytesSync());
        final receipt = r.receipt;
        for (final l in receipt.lines) {
          // ignore: avoid_print
          print(
            '${l.text.padRight(24)} ${l.cents} ${l.quantity ?? ''} '
            '${l.check.name} ${l.votes}×',
          );
        }
        // ignore: avoid_print
        print(
          'Summe ${receipt.sumCents} / Bon ${receipt.totalCents}, '
          'Drehung ${r.quarterTurns}, ${sw.elapsedMilliseconds} ms',
        );
        expect(receipt.balanced, isTrue);
      });
    }, timeout: const Timeout(Duration(minutes: 3)));
  }
}
