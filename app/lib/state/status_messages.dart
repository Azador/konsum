import 'dart:async';

import 'package:flutter/foundation.dart';

/// Eine kurze Meldung, optional mit einer Aktion (z. B. „Rückgängig“).
class StatusMessage {
  const StatusMessage(this.text, {this.actionLabel, this.onAction});

  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;
}

/// Meldungen für die Statuszeile. Eine neue Meldung ersetzt die vorige;
/// jede verschwindet nach [duration] von selbst.
class StatusMessages extends ChangeNotifier {
  StatusMessages({this.duration = const Duration(seconds: 4)});

  final Duration duration;

  /// Wird angezeigt, solange keine Meldung da ist.
  String version = '';

  StatusMessage? _current;
  Timer? _timer;

  StatusMessage? get current => _current;

  void show(String text, {String? actionLabel, VoidCallback? onAction}) {
    _timer?.cancel();
    _current = StatusMessage(
      text,
      actionLabel: actionLabel,
      onAction: onAction,
    );
    _timer = Timer(duration, dismiss);
    notifyListeners();
  }

  void dismiss() {
    _timer?.cancel();
    _timer = null;
    if (_current == null) return;
    _current = null;
    notifyListeners();
  }

  /// Führt die Aktion der aktuellen Meldung aus und blendet sie aus.
  void runAction() {
    final action = _current?.onAction;
    dismiss();
    action?.call();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
