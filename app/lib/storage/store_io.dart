import 'dart:io';

import 'private_dir_io.dart';
import 'store.dart';

Future<KeyValueStore> openStore() async {
  final base = await privateSupportDirectory();
  return FileStore(Directory('${base.path}/data'));
}

/// Eine JSON-Datei pro Schlüssel. Geschrieben wird über eine temporäre Datei,
/// damit ein Absturz beim Schreiben keine halbe Datei hinterlässt.
class FileStore implements KeyValueStore {
  FileStore(this.dir);

  final Directory dir;

  /// Letzter Schreibvorgang je Schlüssel. Schreibvorgänge auf denselben
  /// Schlüssel laufen nacheinander, sonst teilen sie sich die .tmp-Datei.
  final _pending = <String, Future<void>>{};

  File _file(String key) => File('${dir.path}/$key.json');

  @override
  Future<String?> read(String key) async {
    final f = _file(key);
    return await f.exists() ? f.readAsString() : null;
  }

  @override
  Future<void> write(String key, String value) {
    final previous = _pending[key] ?? Future<void>.value();
    final next = previous
        .catchError((Object _) {})
        .then((_) => _write(key, value));
    _pending[key] = next;
    return next.whenComplete(() {
      if (identical(_pending[key], next)) _pending.remove(key);
    });
  }

  Future<void> _write(String key, String value) async {
    await dir.create(recursive: true);
    final f = _file(key);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(value, flush: true);
    await tmp.rename(f.path);
  }

  @override
  Future<void> delete(String key) async {
    final f = _file(key);
    if (await f.exists()) await f.delete();
  }
}
