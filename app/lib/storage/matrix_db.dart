import 'package:matrix/matrix.dart';

import 'matrix_db_io.dart'
    if (dart.library.js_interop) 'matrix_db_web.dart'
    as impl;

/// Die geöffnete Datenbank und ggf. ein Hinweis für die Statuszeile, etwa
/// wenn sie nicht verschlüsselt werden konnte.
typedef MatrixDatabase = ({DatabaseApi database, String? warning});

/// Datenbank des Matrix-SDK: SQLite auf Android/Linux/iOS, IndexedDB im Web.
/// Auf Linux mit SQLCipher verschlüsselt, der Schlüssel liegt in KWallet oder
/// im Secret Service (GNOME-Schlüsselbund, KeePassXC, …).
Future<MatrixDatabase> openMatrixDatabase(String name) => impl.open(name);
