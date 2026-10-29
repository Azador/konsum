import 'package:web/web.dart' as web;

import 'store.dart';

Future<KeyValueStore> openStore() async => WebStore();

/// Speichert im localStorage des Browsers (Präfix `konsum.`).
class WebStore implements KeyValueStore {
  static const _prefix = 'konsum.';

  @override
  Future<String?> read(String key) async =>
      web.window.localStorage.getItem('$_prefix$key');

  @override
  Future<void> write(String key, String value) async =>
      web.window.localStorage.setItem('$_prefix$key', value);

  @override
  Future<void> delete(String key) async =>
      web.window.localStorage.removeItem('$_prefix$key');
}
