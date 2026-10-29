import 'package:flutter/widgets.dart';

import '../state/app_state.dart';

/// Stellt den [AppState] im Widget-Baum bereit und baut bei Änderungen neu.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
    : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
