import 'package:matrix/matrix.dart';

import 'matrix_db_io.dart'
    if (dart.library.js_interop) 'matrix_db_web.dart'
    as impl;

/// Datenbank des Matrix-SDK: SQLite auf Android/Linux/iOS, IndexedDB im Web.
Future<DatabaseApi> openMatrixDatabase(String name) => impl.open(name);
