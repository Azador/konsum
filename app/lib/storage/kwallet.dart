import 'package:dbus/dbus.dart';

import 'secret_store.dart';

/// Zugriff auf die KDE-Brieftasche (KWallet) über D-Bus.
///
/// Wird vor dem Secret Service gefragt: Auf einem KDE-Desktop kann der
/// Secret Service auch von gnome-keyring bedient werden, und bestehende
/// Installationen haben ihren Schlüssel hier.
class KWallet implements SecretStore {
  KWallet._(this._client, this._wallet, this._handle);

  static const _appId = 'Konsum';
  static const _folder = 'Konsum';
  static const _interface = 'org.kde.KWallet';

  final DBusClient _client;
  final DBusRemoteObject _wallet;
  final int _handle;

  @override
  String get name => 'KWallet';

  /// Öffnet die lokale Brieftasche, fragt dabei ggf. nach ihrem Passwort.
  /// null, wenn KWallet fehlt, abgeschaltet ist oder das Öffnen abgelehnt
  /// wurde.
  static Future<KWallet?> open() async {
    final client = DBusClient.session();
    for (final daemon in const ['kwalletd6', 'kwalletd5']) {
      final wallet = DBusRemoteObject(
        client,
        name: 'org.kde.$daemon',
        path: DBusObjectPath('/modules/$daemon'),
      );
      try {
        final enabled = await wallet.callMethod(
          _interface,
          'isEnabled',
          const [],
          replySignature: DBusSignature('b'),
        );
        if (!enabled.values.single.asBoolean()) break;
        final name = await wallet.callMethod(
          _interface,
          'localWallet',
          const [],
          replySignature: DBusSignature('s'),
        );
        final handle = await wallet.callMethod(_interface, 'open', [
          name.values.single,
          const DBusInt64(0),
          const DBusString(_appId),
        ], replySignature: DBusSignature('i'));
        final h = handle.values.single.asInt32();
        if (h < 0) break;
        final kwallet = KWallet._(client, wallet, h);
        await kwallet._ensureFolder();
        return kwallet;
      } on DBusServiceUnknownException {
        continue;
      } on DBusMethodResponseException {
        break;
      }
    }
    await client.close();
    return null;
  }

  Future<void> _ensureFolder() async {
    final has = await _call('hasFolder', [const DBusString(_folder)], 'b');
    if (!has.asBoolean()) {
      await _call('createFolder', [const DBusString(_folder)], 'b');
    }
  }

  @override
  Future<String?> read(String key) async {
    final entry = [const DBusString(_folder), DBusString(key)];
    final has = await _call('hasEntry', entry, 'b');
    if (!has.asBoolean()) return null;
    return (await _call('readPassword', entry, 's')).asString();
  }

  @override
  Future<void> write(String key, String value) async {
    final result = await _call('writePassword', [
      const DBusString(_folder),
      DBusString(key),
      DBusString(value),
    ], 'i');
    if (result.asInt32() != 0) {
      throw StateError('KWallet: Speichern von „$key“ fehlgeschlagen');
    }
  }

  @override
  Future<void> close() async {
    try {
      await _wallet.callMethod(_interface, 'close', [
        DBusInt32(_handle),
        const DBusBoolean(false),
        const DBusString(_appId),
      ], replySignature: DBusSignature('i'));
    } finally {
      await _client.close();
    }
  }

  /// Ruft [method] mit Handle vorn und App-ID hinten auf.
  Future<DBusValue> _call(
    String method,
    List<DBusValue> args,
    String reply,
  ) async {
    final response = await _wallet.callMethod(_interface, method, [
      DBusInt32(_handle),
      ...args,
      const DBusString(_appId),
    ], replySignature: DBusSignature(reply));
    return response.values.single;
  }
}
