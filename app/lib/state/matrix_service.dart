import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:konsum_matrix/konsum_matrix.dart';
import 'package:matrix/matrix.dart';

import '../storage/matrix_db.dart';
import 'app_state.dart';
import 'group_session.dart';

const _backendType = 'matrix';

/// Matrix-Konto der App: Anmeldung, Gruppen teilen, Einladungen annehmen,
/// Gruppen mit ihrem Raum verbinden.
///
/// Ein Konto genügt auch für Gruppen auf anderen Servern: Matrix-Räume
/// sind föderiert, man kann also von seinem Konto aus Räumen auf anderen
/// Servern beitreten.
class MatrixService extends ChangeNotifier {
  MatrixService(this._app);

  final AppState _app;
  Client? _client;
  StreamSubscription<Object?>? _syncSub;
  String? error;
  bool busy = false;

  Client? get client => _client;
  bool get isLoggedIn => _client?.isLogged() ?? false;
  String? get userId => _client?.userID;
  String? get homeserver => _client?.homeserver?.toString();

  MatrixGroups? get _groups => isLoggedIn ? MatrixGroups(_client!) : null;

  /// Offene Einladungen in Konsum-Gruppen.
  List<MatrixGroupRef> get invitations => [
    for (final g in _groups?.groups ?? const <MatrixGroupRef>[])
      if (g.invited) g,
  ];

  /// Öffnet die gespeicherte Sitzung, falls vorhanden. Fehler (z. B. offline)
  /// verhindern den App-Start nicht.
  Future<void> init() async {
    try {
      final client = Client(
        'Konsum',
        database: await openMatrixDatabase('konsum_matrix'),
        requestHistoryOnLimitedTimeline: true,
      );
      _client = client;
      await client.init(waitForFirstSync: false);
      _syncSub = client.onSync.stream.listen((_) => notifyListeners());
      if (isLoggedIn) await connectAll();
    } catch (e) {
      error = 'Matrix nicht verfügbar: $e';
    }
    notifyListeners();
  }

  /// Anmeldung mit Benutzername (oder vollständiger Matrix-ID) und Passwort.
  /// Ohne Server-Angabe wird der Server aus der Matrix-ID ermittelt.
  Future<bool> login({
    required String homeserver,
    required String user,
    required String password,
  }) => _run(() async {
    final client = _client;
    if (client == null) throw StateError(error ?? 'Matrix nicht verfügbar');
    var server = homeserver.trim();
    if (server.isEmpty && user.contains(':')) {
      server = user.substring(user.indexOf(':') + 1);
    }
    if (server.isEmpty) throw ArgumentError('Bitte Server angeben');
    final uri = Uri.parse(server.contains('://') ? server : 'https://$server');
    await client.checkHomeserver(uri);
    await client.login(
      LoginType.mLoginPassword,
      identifier: AuthenticationUserIdentifier(user: user.trim()),
      password: password,
      initialDeviceDisplayName: 'Konsum ${defaultTargetPlatform.name}',
    );
    await connectAll();
  });

  Future<bool> logout() => _run(() async {
    for (final g in _app.groups) {
      if (g.info.backend?['type'] == _backendType) await g.detach();
    }
    await _client?.logout();
  });

  /// Verbindet alle Matrix-Gruppen mit ihrem Raum.
  Future<void> connectAll() async {
    final groups = _groups;
    if (groups == null) return;
    for (final g in _app.groups) {
      final roomId = g.info.backend?['roomId'];
      if (g.info.backend?['type'] != _backendType || roomId is! String) {
        continue;
      }
      if (g.isConnected) continue;
      if (_client!.getRoomById(roomId)?.membership != Membership.join) {
        continue;
      }
      await g.attach(groups.sync(roomId));
    }
  }

  /// Teilt eine bisher lokale Gruppe: legt einen Raum an und verschickt den
  /// vollständigen Stand.
  Future<bool> share(GroupSession session) => _run(() async {
    final roomId = await _groups!.create(session.info.name);
    session.share({'type': _backendType, 'roomId': roomId});
    _app.notifyGroupChanged();
    await session.attach(_groups!.sync(roomId));
  });

  Future<bool> invite(GroupSession session, String userId) =>
      _run(() => _groups!.invite(_roomId(session), userId.trim()));

  Future<List<String>> members(GroupSession session) async =>
      _groups?.members(_roomId(session)) ?? const [];

  /// Nimmt eine Einladung an und legt die Gruppe lokal an.
  Future<bool> join(MatrixGroupRef ref) => _run(() async {
    await _groups!.join(ref.roomId);
    final session = await _app.createGroup(
      ref.name,
      withDefaults: false,
      backend: {'type': _backendType, 'roomId': ref.roomId},
    );
    await session.attach(_groups!.sync(ref.roomId));
  });

  /// Verlässt den Raum und entfernt die Gruppe von diesem Gerät.
  Future<bool> leave(GroupSession session) => _run(() async {
    await _groups!.leave(_roomId(session));
    await _app.removeGroup(session);
  });

  String _roomId(GroupSession session) =>
      session.info.backend!['roomId'] as String;

  Future<bool> _run(Future<void> Function() action) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      await action();
      return true;
    } catch (e) {
      error = e is MatrixException ? e.errorMessage : '$e';
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    super.dispose();
  }
}
