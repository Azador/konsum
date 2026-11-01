import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Das Datenverzeichnis der App, nur für den eigenen Benutzer lesbar.
Future<Directory> privateSupportDirectory() async {
  final dir = await getApplicationSupportDirectory();
  if (Platform.isLinux) await _adoptOldDirectory(dir);
  await dir.create(recursive: true);
  await restrictPermissions(dir.path, '700');
  return dir;
}

/// Bis Version 0.3 hieß die App-ID `de.azador.konsum`. Deren Datenverzeichnis
/// (neben dem neuen) wird einmalig übernommen.
Future<void> _adoptOldDirectory(Directory dir) async {
  if (await dir.exists()) return;
  final old = Directory('${dir.parent.path}/de.azador.konsum');
  if (await old.exists()) await old.rename(dir.path);
}

/// Setzt die Unix-Rechte von [path] (Dart selbst kann das nicht).
Future<void> restrictPermissions(String path, String mode) async {
  if (!Platform.isLinux && !Platform.isMacOS) return;
  final result = await Process.run('chmod', [mode, path]);
  if (result.exitCode != 0) {
    throw FileSystemException('chmod $mode fehlgeschlagen', path);
  }
}
