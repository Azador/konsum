import 'package:matrix/matrix.dart';

Future<DatabaseApi> open(String name) => MatrixSdkDatabase.init(name);
