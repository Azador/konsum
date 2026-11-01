import 'dart:async';
import 'dart:convert';

import 'package:dbus/dbus.dart';

import 'secret_store.dart';

/// Zugriff auf den freedesktop Secret Service über D-Bus
/// (https://specifications.freedesktop.org/secret-service-spec/).
///
/// Bedient von gnome-keyring, KeePassXC, KWallet 6 u. a. Das Geheimnis wird
/// unverschlüsselt („plain“) über den Session-Bus übertragen; den kann
/// ohnehin nur der eigene Benutzer abhören.
class SecretService implements SecretStore {
  SecretService._(this._client, this._service, this._session, this._collection);

  static const _bus = 'org.freedesktop.secrets';
  static const _iService = 'org.freedesktop.Secret.Service';
  static const _iCollection = 'org.freedesktop.Secret.Collection';
  static const _iItem = 'org.freedesktop.Secret.Item';
  static const _iPrompt = 'org.freedesktop.Secret.Prompt';
  static const _iSession = 'org.freedesktop.Secret.Session';
  static const _schema = 'de.azadoro.konsum.Secret';
  static const _none = DBusObjectPath.unchecked('/');

  final DBusClient _client;
  final DBusRemoteObject _service;
  final DBusObjectPath _session;
  final DBusObjectPath _collection;

  @override
  String get name => 'Schlüsselbund';

  /// Öffnet die Standard-Sammlung und entsperrt sie bei Bedarf (der Dienst
  /// fragt dann nach dem Passwort). null, wenn es keinen Secret Service
  /// gibt oder das Entsperren abgelehnt wurde.
  static Future<SecretService?> open() async {
    final client = DBusClient.session();
    final service = DBusRemoteObject(
      client,
      name: _bus,
      path: DBusObjectPath('/org/freedesktop/secrets'),
    );
    try {
      final opened = await service.callMethod(_iService, 'OpenSession', [
        const DBusString('plain'),
        const DBusVariant(DBusString('')),
      ], replySignature: DBusSignature('vo'));
      final session = opened.values[1].asObjectPath();

      var collection = (await service.callMethod(_iService, 'ReadAlias', [
        const DBusString('default'),
      ], replySignature: DBusSignature('o'))).values.single.asObjectPath();
      if (collection == _none) {
        final created = await service.callMethod(
          _iService,
          'CreateCollection',
          [
            DBusDict.stringVariant({
              '$_iCollection.Label': const DBusString('Login'),
            }),
            const DBusString('default'),
          ],
          replySignature: DBusSignature('oo'),
        );
        collection = created.values[0].asObjectPath();
        if (collection == _none) {
          final result = await _prompt(
            client,
            created.values[1].asObjectPath(),
          );
          if (result == null) throw const _Dismissed();
          collection = result.asVariant().asObjectPath();
        }
      }

      final store = SecretService._(client, service, session, collection);
      if (!await store._unlock([collection])) throw const _Dismissed();
      return store;
    } on DBusServiceUnknownException {
      // kein Secret Service
    } on DBusMethodResponseException {
      // Dienst verweigert (z. B. keine Sammlung möglich)
    } on _Dismissed {
      // Entsperren abgelehnt
    }
    await client.close();
    return null;
  }

  Map<String, String> _attributes(String key) => {
    'xdg:schema': _schema,
    'key': key,
  };

  @override
  Future<String?> read(String key) async {
    final found = await _service.callMethod(_iService, 'SearchItems', [
      DBusDict(DBusSignature('s'), DBusSignature('s'), {
        for (final e in _attributes(key).entries)
          DBusString(e.key): DBusString(e.value),
      }),
    ], replySignature: DBusSignature('aoao'));
    final unlocked = found.values[0].asObjectPathArray().toList();
    final locked = found.values[1].asObjectPathArray().toList();
    if (unlocked.isEmpty && locked.isEmpty) return null;
    final item = unlocked.isNotEmpty ? unlocked.first : locked.first;
    if (unlocked.isEmpty && !await _unlock([item])) {
      throw StateError('$name: Entsperren abgelehnt');
    }
    final secret = await DBusRemoteObject(_client, name: _bus, path: item)
        .callMethod(_iItem, 'GetSecret', [
          _session,
        ], replySignature: DBusSignature('(oayays)'));
    final value = secret.values.single.asStruct()[2].asByteArray();
    return utf8.decode(value.toList());
  }

  @override
  Future<void> write(String key, String value) async {
    final attributes = _attributes(key);
    final created =
        await DBusRemoteObject(
          _client,
          name: _bus,
          path: _collection,
        ).callMethod(_iCollection, 'CreateItem', [
          DBusDict.stringVariant({
            '$_iItem.Label': DBusString('Konsum: $key'),
            '$_iItem.Attributes': DBusDict(
              DBusSignature('s'),
              DBusSignature('s'),
              {
                for (final e in attributes.entries)
                  DBusString(e.key): DBusString(e.value),
              },
            ),
          }),
          DBusStruct([
            _session,
            DBusArray.byte(const []),
            DBusArray.byte(utf8.encode(value)),
            const DBusString('text/plain; charset=utf8'),
          ]),
          const DBusBoolean(true),
        ], replySignature: DBusSignature('oo'));
    if (created.values[0].asObjectPath() == _none &&
        await _prompt(_client, created.values[1].asObjectPath()) == null) {
      throw StateError('$name: Speichern von „$key“ abgelehnt');
    }
  }

  @override
  Future<void> close() async {
    try {
      await DBusRemoteObject(_client, name: _bus, path: _session).callMethod(
        _iSession,
        'Close',
        const [],
        replySignature: DBusSignature(''),
      );
    } finally {
      await _client.close();
    }
  }

  /// Entsperrt [objects]; false, wenn der Benutzer abgelehnt hat.
  Future<bool> _unlock(List<DBusObjectPath> objects) async {
    final reply = await _service.callMethod(_iService, 'Unlock', [
      DBusArray.objectPath(objects),
    ], replySignature: DBusSignature('aoo'));
    final prompt = reply.values[1].asObjectPath();
    if (prompt == _none) return true;
    return await _prompt(_client, prompt) != null;
  }

  /// Zeigt den Dialog des Dienstes; das Ergebnis oder null, wenn abgelehnt.
  static Future<DBusValue?> _prompt(
    DBusClient client,
    DBusObjectPath path,
  ) async {
    final prompt = DBusRemoteObject(client, name: _bus, path: path);
    final completed = DBusRemoteObjectSignalStream(
      object: prompt,
      interface: _iPrompt,
      name: 'Completed',
      signature: DBusSignature('bv'),
    ).first;
    await prompt.callMethod(_iPrompt, 'Prompt', const [
      DBusString(''),
    ], replySignature: DBusSignature(''));
    final signal = await completed;
    if (signal.values[0].asBoolean()) return null;
    return signal.values[1];
  }
}

class _Dismissed implements Exception {
  const _Dismissed();
}
