// Nur mit privaten Testdaten: Zuordnung der Testbons zu den echten Artikeln
// der Linux-App (test-privat/gruppe.json = Kopie der Gruppendatei).
import 'dart:convert';
import 'dart:io';

import 'package:konsum_core/konsum_core.dart';
import 'package:test/test.dart';

void main() {
  final groupFile = File('../../test-privat/gruppe.json');
  final dir = Directory('../../test-privat/ocr');
  if (!groupFile.existsSync() || !dir.existsSync()) return;
  test('Zuordnung mit echten Artikeln', () {
    final g = Group(HlcClock('test'));
    final json = jsonDecode(groupFile.readAsStringSync()) as Map;
    g.receive([
      for (final c in json['snapshot'] as List)
        Change.fromJson((c as Map).cast<String, Object?>()),
    ]);
    for (final bon in dir.listSync().whereType<Directory>()) {
      final r = readReceipt([
        for (final f in bon.listSync().whereType<File>())
          f.readAsStringSync(),
      ]);
      final shop = shopFromReceipt(g, r.header);
      final m = ReceiptMatcher(g, shopId: shop?.id);
      print('## ${bon.path.split('/').last} (Laden: ${shop?.name})');
      for (final l in r.lines) {
        final x = m.match(l);
        final name = x.articleId == null ? '' : g.article(x.articleId!)!.name;
        print('${l.text.padRight(22)} ${x.confident ? '✓' : (name.isEmpty ? '–' : '?')} '
            '$name (${x.score.toStringAsFixed(2)})');
      }
    }
  });
}
