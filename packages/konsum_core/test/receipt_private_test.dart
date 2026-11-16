// Läuft nur, wenn private Testdaten vorliegen (test-privat/, nicht im Repo):
// test-privat/ocr/<bon>/*.txt sind OCR-Läufe eines Bons.
import 'dart:io';

import 'package:konsum_core/konsum_core.dart';
import 'package:test/test.dart';

void main() {
  final dir = Directory('../../test-privat/ocr');
  if (!dir.existsSync()) return;
  for (final bon in dir.listSync().whereType<Directory>()) {
    test('privater Bon ${bon.path.split('/').last}', () {
      final runs = [
        for (final f in bon.listSync().whereType<File>())
          if (f.path.endsWith('.txt')) f.readAsStringSync(),
      ];
      final r = readReceipt(runs);
      for (final l in r.lines) {
        print(
          '${l.text.padRight(24)} ${l.cents} ${l.quantity ?? ''} '
          '${l.check.name} ${l.votes}× ${l.prices}',
        );
      }
      print('Summe ${r.sumCents} / Bon ${r.totalCents}');
      expect(r.balanced, isTrue);
    });
  }
}
