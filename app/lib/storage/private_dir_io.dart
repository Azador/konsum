import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Das Datenverzeichnis der App, nur für den eigenen Benutzer lesbar.
Future<Directory> privateSupportDirectory() async {
  final dir = await getApplicationSupportDirectory();
  await dir.create(recursive: true);
  await restrictPermissions(dir.path, '700');
  return dir;
}

/// Setzt die Unix-Rechte von [path] (Dart selbst kann das nicht).
Future<void> restrictPermissions(String path, String mode) async {
  if (!Platform.isLinux && !Platform.isMacOS) return;
  final result = await Process.run('chmod', [mode, path]);
  if (result.exitCode != 0) {
    throw FileSystemException('chmod $mode fehlgeschlagen', path);
  }
}
