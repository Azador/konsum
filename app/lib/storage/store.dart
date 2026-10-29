import 'store_io.dart' if (dart.library.js_interop) 'store_web.dart' as impl;

/// Einfacher Schlüssel-Wert-Speicher für die lokalen Daten.
abstract interface class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Öffnet den Speicher der Plattform: Dateien auf Android/Linux/iOS,
/// localStorage im Browser.
Future<KeyValueStore> openStore() => impl.openStore();

class MemoryStore implements KeyValueStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}
