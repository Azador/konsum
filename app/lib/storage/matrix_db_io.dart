import 'dart:io';
import 'dart:math';

import 'package:matrix/matrix.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'matrix_db.dart';
import 'private_dir_io.dart';
import 'secret_store.dart';

Future<bool> exists(String name) async {
  final dir = await privateSupportDirectory();
  return File('${dir.path}/$name.sqlite').exists();
}

Future<MatrixDatabase> open(String name) async {
  final DatabaseFactory factory;
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    sqfliteFfiInit();
    factory = databaseFactoryFfi;
  } else {
    factory = sqflite.databaseFactory;
  }
  final dir = await privateSupportDirectory();
  final path = '${dir.path}/$name.sqlite';

  String? warning;
  OnDatabaseConfigureFn? onConfigure;
  if (Platform.isLinux) {
    final cipher = await _cipher(name, path);
    if (cipher == null) {
      warning =
          'Kein Schlüsselbund (KWallet, GNOME-Schlüsselbund …) verfügbar – '
          'Matrix-Zugangsdaten liegen unverschlüsselt auf der Platte.';
    } else {
      final helper = SQfLiteEncryptionHelper(
        factory: factory,
        path: path,
        cipher: cipher.key,
      );
      await helper.ensureDatabaseFileEncrypted();
      onConfigure = helper.applyPragmaKey;
      warning = cipher.warning;
    }
  }

  final db = await factory.openDatabase(
    path,
    options: OpenDatabaseOptions(onConfigure: onConfigure),
  );
  for (final suffix in const ['', '-journal', '-wal', '-shm']) {
    if (await File('$path$suffix').exists()) {
      await restrictPermissions('$path$suffix', '600');
    }
  }
  return (
    database: await MatrixSdkDatabase.init(
      name,
      database: db,
      sqfliteFactory: factory,
    ),
    warning: warning,
  );
}

/// Schlüssel der Datenbank aus dem Schlüsselbund; beim ersten Mal wird er
/// erzeugt. null, wenn kein Schlüsselbund erreichbar ist und die Datenbank noch
/// unverschlüsselt ist (bzw. fehlt).
Future<({String key, String? warning})?> _cipher(
  String name,
  String path,
) async {
  final file = File(path);
  final wallet = await openSecretStore();
  if (wallet == null) {
    if (await file.exists() && !await _isPlainText(file)) {
      throw StateError(
        'Kein Schlüsselbund verfügbar – ohne ihn lassen sich die '
        'verschlüsselten Matrix-Daten nicht öffnen.',
      );
    }
    return null;
  }
  try {
    final entry = 'matrix-db-$name';
    final key = await wallet.read(entry);
    if (key != null) return (key: key, warning: null);

    String? warning;
    if (await file.exists() && !await _isPlainText(file)) {
      // Verschlüsselt, aber der Schlüssel ist weg (Brieftasche gelöscht?):
      // nicht mehr zu öffnen. Beiseitelegen statt löschen.
      await file.rename('$path.unlesbar');
      warning =
          'Schlüssel der Matrix-Daten fehlt in ${wallet.name} – '
          'bitte neu anmelden.';
    }
    final random = Random.secure();
    final created = [
      for (var i = 0; i < 32; i++)
        random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
    await wallet.write(entry, created);
    return (key: created, warning: warning);
  } finally {
    await wallet.close();
  }
}

/// Ob [file] mit dem Kopf einer unverschlüsselten SQLite-Datei beginnt.
Future<bool> _isPlainText(File file) async {
  final raf = await file.open();
  try {
    final header = await raf.read(16);
    return String.fromCharCodes(header) == 'SQLite format 3\x00';
  } finally {
    await raf.close();
  }
}
