import 'dart:js_interop';

import 'package:matrix/matrix.dart';
import 'package:web/web.dart' as web;

import 'matrix_db.dart';

Future<bool> exists(String name) async {
  try {
    final databases = (await web.window.indexedDB.databases().toDart).toDart;
    return databases.any((d) => d.name == name);
  } catch (_) {
    // Browser ohne databases(): lieber öffnen als eine Sitzung verlieren.
    return true;
  }
}

Future<MatrixDatabase> open(String name) async =>
    (database: await MatrixSdkDatabase.init(name), warning: null);
