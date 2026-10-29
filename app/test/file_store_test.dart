import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:konsum/storage/store_io.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('konsum_store'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('gleichzeitige Schreibvorgänge auf denselben Schlüssel', () async {
    final store = FileStore(Directory('${dir.path}/data'));
    await Future.wait([for (var i = 0; i < 20; i++) store.write('app', '$i')]);
    expect(await store.read('app'), '19');
    expect(File('${dir.path}/data/app.json.tmp').existsSync(), isFalse);
  });
}
