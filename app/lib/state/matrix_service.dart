import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;
import 'package:konsum_matrix/konsum_matrix.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:url_launcher/url_launcher.dart';

import '../storage/matrix_db.dart';
import 'app_state.dart';
import 'group_session.dart';
import 'oidc_redirect.dart';

const _backendType = 'matrix';

/// Wie man sich an einem Server anmelden kann.
class ServerLogin {
  const ServerLogin({
    required this.homeserver,
    required this.browser,
    required this.canRegister,
    required this.password,
  });

  final Uri homeserver;

  /// Anmeldung auf der Webseite des Servers (OIDC), z. B. matrix.org.
  final bool browser;

  /// Neues Konto über die Webseite des Servers.
  final bool canRegister;

  /// Klassische Anmeldung mit Passwort in der App.
  final bool password;
}

/// Ob andere Geräte diesem Gerät vertrauen.
enum SessionTrust {
  /// Nicht angemeldet, ohne Verschlüsselung oder Schlüssel noch nicht geladen.
  unknown,

  /// Für das Konto ist kein Cross-Signing eingerichtet.
  noCrossSigning,

  unverified,
  verified,
}

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
  StreamSubscription<Object?>? _verificationSub;
  String? error;
  bool busy = false;

  /// Läuft gerade eine Anmeldung im Browser?
  bool waitingForBrowser = false;
  Completer<Never>? _browserCancel;

  /// Ob Ende-zu-Ende-Verschlüsselung verfügbar ist. Im Web nur, wenn
  /// vodozemac als WASM mitgebaut wurde und die Seite cross-origin-isoliert
  /// ausgeliefert wird.
  bool get encryptionEnabled => _client?.encryptionEnabled ?? false;

  Client? get client => _client;
  bool get isLoggedIn => _client?.isLogged() ?? false;
  String? get userId => _client?.userID;
  String? get homeserver => _client?.homeserver?.toString();

  /// Die laufende Verifizierung, ausgehend oder von einem anderen Gerät
  /// angefragt; null, wenn keine läuft.
  KeyVerification? verification;

  SessionTrust get sessionTrust {
    final client = _client;
    final encryption = client?.encryption;
    if (client == null || !client.isLogged() || encryption == null) {
      return SessionTrust.unknown;
    }
    final keys = client.userDeviceKeys[client.userID];
    if (keys?.deviceKeys[client.deviceID] == null) return SessionTrust.unknown;
    if (keys!.masterKey == null) return SessionTrust.noCrossSigning;
    return encryption.crossSigning.isSelfSigned
        ? SessionTrust.verified
        : SessionTrust.unverified;
  }

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
      try {
        // Im Web aus web/pkg (siehe deploy/web/build-vodozemac.sh).
        await vod.init();
        Logs().i('Verschlüsselung (vodozemac) geladen');
      } catch (e) {
        debugPrint('Verschlüsselung nicht verfügbar: $e');
      }
      final db = await openMatrixDatabase('konsum_matrix');
      if (db.warning != null) _app.status.show(db.warning!);
      final client = Client(
        'Konsum',
        database: db.database,
        // Konsum-Ereignisse verschicken nur Konsum-Geräte, und die können
        // (noch) nicht verifizieren. Mit der Standardeinstellung bekämen
        // Konsum-Geräte von Konten mit Cross-Signing (z. B. durch Element)
        // keine Schlüssel und könnten nichts entschlüsseln.
        shareKeysWith: ShareKeysWith.all,
        // QR-Codes nicht: Dafür bräuchte es die Kamera auch unter Linux.
        verificationMethods: {
          KeyVerificationMethod.emoji,
          KeyVerificationMethod.numbers,
        },
      );
      _client = client;
      await client.init(waitForFirstSync: false);
      _syncSub = client.onSync.stream.listen((_) {
        _adoptRoomNames();
        notifyListeners();
        unawaited(_adoptJoinedRooms());
      });
      _verificationSub = client.onKeyVerificationRequest.stream.listen(_track);
      if (isLoggedIn) await connectAll();
    } catch (e) {
      error = 'Matrix nicht verfügbar: $e';
    }
    notifyListeners();
  }

  /// Prüft den Server und ermittelt, wie man sich anmelden kann. [input] ist
  /// ein Servername, eine Adresse oder eine Matrix-ID (`@name:server`).
  Future<ServerLogin?> checkServer(String input) async {
    ServerLogin? result;
    await _run(() async {
      final client = _client;
      if (client == null) throw StateError(error ?? 'Matrix nicht verfügbar');
      var server = input.trim();
      if (server.startsWith('@') && server.contains(':')) {
        server = server.substring(server.indexOf(':') + 1);
      }
      if (server.isEmpty) throw ArgumentError('Bitte Server angeben');
      final uri = Uri.parse(
        server.contains('://') ? server : 'https://$server',
      );
      final (_, _, loginTypes, authMetadata) = await client.checkHomeserver(
        uri,
      );
      result = ServerLogin(
        homeserver: client.homeserver!,
        browser: authMetadata != null && browserLoginAvailable,
        canRegister:
            authMetadata != null &&
            browserLoginAvailable &&
            (authMetadata.promptValuesSupported?.contains('create') ?? false),
        password: loginTypes.any((t) => t.type == LoginType.mLoginPassword),
      );
    });
    return result;
  }

  /// Im Web fehlt dafür noch der Rückweg vom Server auf die Seite.
  bool get browserLoginAvailable => !kIsWeb;

  /// Anmeldung mit Benutzername (oder vollständiger Matrix-ID) und Passwort
  /// an dem Server aus [checkServer].
  Future<bool> login({required String user, required String password}) =>
      _run(() async {
        final client = _client;
        if (client == null || client.homeserver == null) {
          throw StateError('Bitte zuerst den Server prüfen');
        }
        await client.login(
          LoginType.mLoginPassword,
          identifier: AuthenticationUserIdentifier(user: user.trim()),
          password: password,
          initialDeviceDisplayName: 'Konsum ${defaultTargetPlatform.name}',
        );
        await connectAll();
      });

  /// Anmeldung oder Registrierung ([register]) auf der Webseite des Servers
  /// aus [checkServer]. Öffnet den Browser und wartet auf die Rückkehr.
  Future<bool> loginWithBrowser({bool register = false}) => _run(() async {
    final client = _client;
    if (client == null || client.homeserver == null) {
      throw StateError('Bitte zuerst den Server prüfen');
    }
    final redirect = await openOidcRedirect();
    if (redirect == null) {
      throw UnsupportedError('Anmeldung im Browser geht hier noch nicht');
    }
    final cancel = _browserCancel = Completer<Never>();
    waitingForBrowser = true;
    notifyListeners();
    try {
      final clientData = await client.registerOidcClient(
        redirectUris: [redirect.redirectUri],
        applicationType: OidcApplicationType.native,
        clientInformation: OidcClientInformation(
          clientName: 'Konsum',
          // Der Host muss das umgekehrte App-Schema sein (de.azadoro.konsum).
          clientUri: Uri.parse('https://konsum.azadoro.de'),
          logoUri: Uri.parse('https://konsum.azadoro.de/icon.png'),
          tosUri: null,
          policyUri: Uri.parse('https://konsum.azadoro.de/datenschutz.html'),
        ),
      );
      final session = await client.initOidcLoginSession(
        oidcClientData: clientData,
        redirectUri: redirect.redirectUri,
        prompt: register ? 'create' : null,
      );
      final opened = await launchUrl(
        session.authenticationUri,
        mode: LaunchMode.externalApplication,
      );
      if (!opened) throw StateError('Browser konnte nicht geöffnet werden');
      final result = await Future.any([redirect.wait(), cancel.future]);
      final params = result.queryParameters;
      final failure = params['error'];
      if (failure != null) {
        throw StateError(
          failure == 'access_denied'
              ? 'Anmeldung abgebrochen'
              : params['error_description'] ?? failure,
        );
      }
      await client.oidcLogin(
        session: session,
        code: params['code'] ?? '',
        state: params['state'] ?? '',
      );
      await connectAll();
    } finally {
      waitingForBrowser = false;
      _browserCancel = null;
      await redirect.close();
    }
  });

  /// Bricht das Warten auf den Browser ab.
  void cancelBrowserLogin() {
    final cancel = _browserCancel;
    if (cancel != null && !cancel.isCompleted) {
      cancel.completeError(StateError('Anmeldung abgebrochen'));
    }
  }

  Future<bool> logout() => _run(() async {
    for (final g in _app.groups) {
      if (g.info.backend?['type'] == _backendType) await g.detach();
    }
    await _client?.logout();
  });

  /// Öffnet im Browser die Seite des Servers, auf der man das Konto löscht.
  /// Server ohne Kontoverwaltung (ältere ohne Anmeldung über den Browser):
  /// die Erklärung auf der Projektseite.
  Future<bool> openAccountDeletion() => _run(() async {
    final client = _client;
    if (client == null) throw StateError('Matrix nicht verfügbar');
    Uri target = accountDeletionHelp;
    try {
      // Roh abgefragt: Das SDK macht aus unbekannten Aktionen „profile“.
      final metadata = await client.request(
        RequestType.GET,
        '/client/v1/auth_metadata',
      );
      final manage = metadata['account_management_uri'];
      if (manage is String) {
        const action = 'org.matrix.account_deactivate';
        final actions = metadata['account_management_actions_supported'];
        final uri = Uri.parse(manage);
        target = actions is List && actions.contains(action)
            ? uri.replace(
                queryParameters: {...uri.queryParameters, 'action': action},
              )
            : uri;
      }
    } catch (_) {
      // Server ohne Anmeldung über den Browser: Erklärung zeigen.
    }
    final opened = await launchUrl(
      target,
      mode: LaunchMode.externalApplication,
    );
    if (!opened) throw StateError('Browser konnte nicht geöffnet werden');
  });

  static final accountDeletionHelp = Uri.parse(
    'https://konsum.azadoro.de/datenschutz.html#konto-loeschen',
  );

  /// Bittet die anderen Geräte des Kontos, dieses Gerät zu bestätigen
  /// (Emojis vergleichen).
  Future<bool> verifyWithOtherDevice() => _run(() async {
    final keys = _client!.userDeviceKeys[_client!.userID];
    if (keys == null) throw StateError('Geräteschlüssel noch nicht geladen');
    _track(await keys.startVerification());
  });

  /// Bestätigt dieses Gerät mit dem Wiederherstellungsschlüssel oder der
  /// Sicherheits-Passphrase des Kontos.
  Future<bool> verifyWithRecoveryKey(String key) => _run(() async {
    try {
      await _client!.encryption!.crossSigning.selfSign(
        keyOrPassphrase: key.trim(),
      );
    } on InvalidPassphraseException {
      throw StateError('Schlüssel oder Passphrase stimmt nicht');
    } on Exception catch (e) {
      if ('$e'.contains('Bad MAC')) {
        throw StateError('Schlüssel oder Passphrase stimmt nicht');
      }
      rethrow;
    }
  });

  /// Merkt sich [request] als laufende Verifizierung. Läuft schon eine,
  /// wird die neue abgelehnt.
  void _track(KeyVerification request) {
    final current = verification;
    if (current != null && current != request && !current.isDone) {
      unawaited(request.rejectVerification());
      return;
    }
    verification = request..onUpdate = notifyListeners;
    notifyListeners();
  }

  /// Schließt die Verifizierung; bricht sie ab, wenn sie noch läuft.
  Future<void> closeVerification() async {
    final current = verification;
    verification = null;
    notifyListeners();
    if (current != null && !current.isDone) await current.cancel('m.user');
  }

  /// Verbindet alle Matrix-Gruppen mit ihrem Raum.
  Future<void> connectAll() async {
    final groups = _groups;
    if (groups == null) return;
    await _adoptJoinedRooms();
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

  /// Raum-IDs, die gerade übernommen werden (onSync feuert oft).
  final _adopting = <String>{};

  /// Solange [share] oder [join] laufen, ist ihr Raum schon beigetreten,
  /// gehört aber noch zu keiner Gruppe; nicht doppelt anlegen.
  int _adoptionPaused = 0;

  Future<void> _withoutAdopting(Future<void> Function() action) async {
    _adoptionPaused++;
    try {
      await action();
    } finally {
      _adoptionPaused--;
    }
  }

  /// Legt Gruppen an für Konsum-Räume, denen das Konto schon beigetreten ist,
  /// die es auf diesem Gerät aber noch nicht gibt: neues Gerät desselben
  /// Kontos oder Beitritt mit einem anderen Programm (z. B. Element).
  Future<void> _adoptJoinedRooms() async {
    final groups = _groups;
    if (groups == null || _adoptionPaused > 0) return;
    final known = {
      for (final g in _app.groups)
        if (g.info.backend?['type'] == _backendType) g.info.backend!['roomId'],
    };
    var adopted = 0;
    for (final ref in groups.groups) {
      if (ref.invited ||
          known.contains(ref.roomId) ||
          !_adopting.add(ref.roomId)) {
        continue;
      }
      try {
        // Die leere Startgruppe eines frischen Geräts würde sonst vor der
        // geteilten Gruppe angezeigt.
        await _app.removeUnusedGroups();
        final session = await _app.createGroup(
          ref.name,
          withDefaults: false,
          backend: {'type': _backendType, 'roomId': ref.roomId},
        );
        await session.attach(groups.sync(ref.roomId));
        adopted++;
      } finally {
        _adopting.remove(ref.roomId);
      }
    }
    if (adopted > 0) {
      _app.status.show(
        adopted == 1
            ? 'Geteilte Gruppe übernommen, Daten werden geladen …'
            : '$adopted geteilte Gruppen übernommen, Daten werden geladen …',
      );
    }
  }

  /// Übernimmt geänderte Raumnamen (von einem anderen Gerät, Mitglied oder
  /// Programm wie Element) als Gruppennamen.
  void _adoptRoomNames() {
    for (final g in _app.groups) {
      if (!isShared(g)) continue;
      final name = _client?.getRoomById(_roomId(g))?.name ?? '';
      if (name.isNotEmpty && name != g.info.name) _app.renameGroup(g, name);
    }
  }

  /// Ob die Gruppe über einen Matrix-Raum geteilt ist.
  bool isShared(GroupSession session) =>
      session.info.backend?['type'] == _backendType &&
      session.info.backend?['roomId'] is String;

  /// Benennt eine geteilte Gruppe um: Der Raumname ist der Gruppenname für
  /// alle Mitglieder und Geräte. Lokal erst, wenn der Server zugestimmt hat,
  /// sonst holte [_adoptRoomNames] den alten Namen zurück.
  Future<bool> rename(GroupSession session, String name) => _run(() async {
    final groups = _groups;
    if (groups == null) throw StateError('Nicht bei Matrix angemeldet');
    await groups.rename(_roomId(session), name);
    _app.renameGroup(session, name);
  });

  /// Teilt eine bisher lokale Gruppe: legt einen Raum an und verschickt den
  /// vollständigen Stand.
  Future<bool> share(GroupSession session) => _run(
    () => _withoutAdopting(() async {
      final roomId = await _groups!.create(session.info.name);
      session.share({'type': _backendType, 'roomId': roomId});
      _app.notifyGroupChanged();
      await session.attach(_groups!.sync(roomId));
    }),
  );

  Future<bool> invite(GroupSession session, String userId) =>
      _run(() => _groups!.invite(_roomId(session), userId.trim()));

  Future<List<String>> members(GroupSession session) async =>
      _groups?.members(_roomId(session)) ?? const [];

  /// Nimmt eine Einladung an und legt die Gruppe lokal an.
  Future<bool> join(MatrixGroupRef ref) => _run(
    () => _withoutAdopting(() async {
      await _groups!.join(ref.roomId);
      final session = await _app.createGroup(
        ref.name,
        withDefaults: false,
        backend: {'type': _backendType, 'roomId': ref.roomId},
      );
      await session.attach(_groups!.sync(ref.roomId));
    }),
  );

  /// Verlässt den Raum und entfernt die Gruppe von diesem Gerät.
  Future<bool> leave(GroupSession session) => _run(() async {
    await _groups!.leave(_roomId(session));
    await _app.removeGroup(session);
  });

  /// Ob der Raum der Gruppe Ende-zu-Ende-verschlüsselt ist (null: unbekannt).
  bool? isEncrypted(GroupSession session) =>
      _client?.getRoomById(_roomId(session))?.encrypted;

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
      error = switch (e) {
        MatrixException() => e.errorMessage,
        OidcException() => e.errorDescription ?? e.error,
        StateError() => e.message,
        UnsupportedError() => e.message ?? '$e',
        ArgumentError() => '${e.message}',
        _ => '$e',
      };
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    _verificationSub?.cancel();
    super.dispose();
  }
}
