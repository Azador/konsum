import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'state/app_state.dart';
import 'state/matrix_service.dart';
import 'storage/store.dart';
import 'ui/dialogs.dart';
import 'ui/drawer.dart';
import 'ui/list_page.dart';
import 'ui/scope.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('de');
  final state = await AppState.load(await openStore());
  final matrix = MatrixService(state);
  Timer.periodic(const Duration(seconds: 30), (_) {
    state.flushAll();
    if (matrix.isLoggedIn) matrix.connectAll();
  });
  runApp(KonsumApp(state: state, matrix: matrix));
  // Erst nach dem Start: Die Liste soll auch ohne Netz sofort da sein.
  unawaited(matrix.init());
}

class KonsumApp extends StatelessWidget {
  const KonsumApp({super.key, required this.state, this.matrix});

  final AppState state;
  final MatrixService? matrix;

  @override
  Widget build(BuildContext context) {
    final app = AppScope(
      state: state,
      child: MaterialApp(
        title: 'Konsum',
        theme: ThemeData(colorSchemeSeed: Colors.green),
        darkTheme: ThemeData(
          colorSchemeSeed: Colors.green,
          brightness: Brightness.dark,
        ),
        locale: const Locale('de'),
        supportedLocales: const [Locale('de')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const HomePage(),
      ),
    );
    return matrix == null ? app : MatrixScope(service: matrix!, child: app);
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final group = app.currentGroup;
    final listId = app.currentListId;
    if (group != null && listId != null) {
      return ListPage(
        key: ValueKey('${group.id}/$listId'),
        session: group,
        listId: listId,
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Konsum')),
      drawer: const GroupDrawer(),
      body: Center(
        child: FilledButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('Neue Liste'),
          onPressed: () async {
            final name = await promptText(context, title: 'Neue Liste');
            if (name == null) return;
            final g = group ?? await app.createGroup('Zuhause');
            app.createList(g, name);
          },
        ),
      ),
    );
  }
}
