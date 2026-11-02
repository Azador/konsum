import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

/// Wo die Einrichtung gerade steht.
enum KeySetupStep {
  /// Schlüssel werden erzeugt und hochgeladen.
  working,

  /// Der Server will das Ersetzen der Identität im Browser bestätigt haben
  /// (z. B. matrix.org über seinen Kontodienst).
  approveInBrowser,

  /// Der Server will das Passwort des Kontos.
  password,

  /// Fertig, [KeySetup.recoveryKey] ist gesetzt.
  done,

  failed,
}

/// Richtet die Geräte-Verifizierung des Kontos ein: Cross-Signing-Schlüssel,
/// Schlüsselspeicher (SSSS) mit neuem Wiederherstellungsschlüssel und
/// Online-Sicherung der Raumschlüssel. Dieses Gerät gilt danach als
/// verifiziert und kann weitere Geräte (z. B. Element) bestätigen.
///
/// Gibt es schon eine Identität, wird sie ersetzt. Andere Geräte gelten
/// danach als nicht verifiziert, bis man sie neu bestätigt.
class KeySetup extends ChangeNotifier {
  KeySetup(this._client) {
    _uiaSub = _client.onUiaRequest.stream.listen(_onUia);
    unawaited(_drive(_client.encryption!.bootstrap()));
  }

  final Client _client;
  late final StreamSubscription<UiaRequest> _uiaSub;
  UiaRequest? _uia;

  KeySetupStep step = KeySetupStep.working;

  /// Der neue Wiederherstellungsschlüssel, sobald [step] done ist.
  String? recoveryKey;

  /// Seite zum Bestätigen im Browser, solange [step] approveInBrowser ist.
  Uri? approvalUrl;

  /// Ob der Server die vorige Bestätigung (Browser oder Passwort) nicht
  /// angenommen hat.
  bool retry = false;

  String? error;

  Future<void> _drive(Bootstrap b) async {
    try {
      while (true) {
        switch (b.state) {
          case BootstrapState.askWipeSsss:
            b.wipeSsss(true);
          case BootstrapState.askNewSsss:
            await b.newSsss();
          case BootstrapState.askWipeCrossSigning:
            await b.wipeCrossSigning(true);
          case BootstrapState.askSetupCrossSigning:
            await b.askSetupCrossSigning(
              setupMasterKey: true,
              setupSelfSigningKey: true,
              setupUserSigningKey: true,
            );
          case BootstrapState.askWipeOnlineKeyBackup:
            b.wipeOnlineKeyBackup(true);
          case BootstrapState.askSetupOnlineKeyBackup:
            await b.askSetupOnlineKeyBackup(true);
          case BootstrapState.done:
            recoveryKey = b.newSsssKey?.recoveryKey;
            if (recoveryKey == null) throw StateError('Kein Schlüssel erzeugt');
            _finish(KeySetupStep.done);
            return;
          case BootstrapState.error:
            throw b.errorResult?.error ?? StateError('unbekannter Fehler');
          // Nach wipeSsss(true) kommen diese nicht vor; loading nur während
          // eines der obigen Aufrufe.
          case BootstrapState.loading ||
              BootstrapState.askUseExistingSsss ||
              BootstrapState.askUnlockSsss ||
              BootstrapState.askBadSsss ||
              BootstrapState.openExistingSsss:
            throw StateError('Unerwarteter Schritt ${b.state.name}');
        }
      }
    } catch (e) {
      error = switch (e) {
        MatrixException() => e.errorMessage,
        StateError() => e.message,
        _Aborted() => e.message,
        _ => '$e',
      };
      _finish(KeySetupStep.failed);
    }
  }

  void _finish(KeySetupStep result) {
    unawaited(_uiaSub.cancel());
    _uia = null;
    step = result;
    if (!_disposed) notifyListeners();
  }

  void _onUia(UiaRequest uia) {
    if (uia.state != UiaRequestState.waitForUser) return;
    retry = _uia == uia;
    _uia = uia;
    if (uia.nextStages.contains(AuthenticationTypes.password)) {
      step = KeySetupStep.password;
    } else if (_urlOf(uia) case final url?) {
      approvalUrl = url;
      step = KeySetupStep.approveInBrowser;
    } else {
      uia.cancel(
        _Aborted(
          'Der Server verlangt eine Bestätigung, die Konsum nicht kennt '
          '(${uia.nextStages.join(', ')}).',
        ),
      );
      return;
    }
    notifyListeners();
  }

  /// Seite für Stufen wie org.matrix.cross_signing_reset oder m.oauth.
  static Uri? _urlOf(UiaRequest uia) {
    for (final stage in uia.nextStages) {
      final params = uia.params[stage];
      if (params is Map && params['url'] is String) {
        return Uri.tryParse(params['url'] as String);
      }
    }
    return null;
  }

  /// Nach der Bestätigung im Browser: Hochladen erneut versuchen.
  void approved() => _continue(AuthenticationData(session: _uia?.session));

  void submitPassword(String password) => _continue(
    AuthenticationPassword(
      session: _uia?.session,
      password: password,
      identifier: AuthenticationUserIdentifier(user: _client.userID!),
    ),
  );

  void _continue(AuthenticationData auth) {
    final uia = _uia;
    if (uia == null) return;
    step = KeySetupStep.working;
    notifyListeners();
    unawaited(uia.completeStage(auth));
  }

  /// Bricht eine wartende Bestätigung ab; die Einrichtung schlägt dann fehl.
  void cancel() {
    _uia?.cancel(const _Aborted('Abgebrochen'));
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    cancel();
    unawaited(_uiaSub.cancel());
    super.dispose();
  }
}

class _Aborted implements Exception {
  const _Aborted(this.message);

  final String message;

  @override
  String toString() => message;
}
