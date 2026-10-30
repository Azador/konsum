import 'package:matrix/matrix.dart';

import 'matrix_db.dart';

Future<MatrixDatabase> open(String name) async =>
    (database: await MatrixSdkDatabase.init(name), warning: null);
