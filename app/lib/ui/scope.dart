import 'package:flutter/widgets.dart';

import '../state/app_state.dart';
import '../state/matrix_service.dart';

/// Stellt den [AppState] im Widget-Baum bereit und baut bei Änderungen neu.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
    : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

/// Stellt den [MatrixService] bereit (fehlt z. B. in Tests).
class MatrixScope extends InheritedNotifier<MatrixService> {
  const MatrixScope({
    super.key,
    required MatrixService service,
    required super.child,
  }) : super(notifier: service);

  static MatrixService? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MatrixScope>()?.notifier;
}
