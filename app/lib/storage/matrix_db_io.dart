import 'dart:io';

import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<DatabaseApi> open(String name) async {
  final DatabaseFactory factory;
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    sqfliteFfiInit();
    factory = databaseFactoryFfi;
  } else {
    factory = sqflite.databaseFactory;
  }
  final dir = await getApplicationSupportDirectory();
  final db = await factory.openDatabase('${dir.path}/$name.sqlite');
  return MatrixSdkDatabase.init(name, database: db, sqfliteFactory: factory);
}
