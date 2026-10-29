import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'store.dart';

Future<KeyValueStore> openStore() async {
  final base = await getApplicationSupportDirectory();
  return FileStore(Directory('${base.path}/data'));
}

/// Eine JSON-Datei pro Schlüssel. Geschrieben wird über eine temporäre Datei,
/// damit ein Absturz beim Schreiben keine halbe Datei hinterlässt.
class FileStore implements KeyValueStore {
  FileStore(this.dir);

  final Directory dir;

  File _file(String key) => File('${dir.path}/$key.json');

  @override
  Future<String?> read(String key) async {
    final f = _file(key);
    return await f.exists() ? f.readAsString() : null;
  }

  @override
  Future<void> write(String key, String value) async {
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
