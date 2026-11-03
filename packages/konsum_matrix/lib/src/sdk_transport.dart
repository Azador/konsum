import 'dart:async';

import 'package:matrix/matrix.dart';

import 'transport.dart';

/// [RoomTransport] über das Matrix-SDK. Das SDK übernimmt Sync,
/// Verschlüsselung und Wiederholungen beim Senden.
class SdkRoomTransport implements RoomTransport {
  SdkRoomTransport(this.client, this.roomId, {this.keyTimeout = _keyTimeout});

  /// Wie lange auf den Schlüssel eines verschlüsselten Ereignisses gewartet
  /// wird, bevor die Lücke per Schnappschuss geschlossen wird.
  static const _keyTimeout = Duration(minutes: 2);

  final Client client;
  final String roomId;
  final Duration keyTimeout;

  late final _events = StreamController<RoomEvent>(
    onListen: _start,
    onCancel: _stop,
  );
  final _gaps = StreamController<void>.broadcast();
  final _subs = <StreamSubscription<Object?>>[];

  /// Ereignisse, deren Schlüssel noch fehlt, nach Megolm-Session.
  final _undecrypted = <String, List<Event>>{};
  final _keyTimers = <String, Timer>{};

  Room get _room {
    final room = client.getRoomById(roomId);
    if (room == null) throw StateError('Raum $roomId unbekannt');
    return room;
  }

  @override
  String get userId => client.userID!;

  @override
  String get deviceId => client.deviceID!;

  @override
  Stream<RoomEvent> get events => _events.stream;

  @override
  Stream<void> get gaps => _gaps.stream;

  @override
  Stream<void> get synced => client.onSync.stream
      .where((sync) => sync.rooms?.join?[roomId]?.timeline?.limited != true)
      .map((_) {});

  void _start() {
    _subs
      ..add(
        client.onTimelineEvent.stream
            .where((e) => e.roomId == roomId)
            .listen(_onTimelineEvent),
      )
      ..add(
        client.onSync.stream
            .where(
              (sync) => sync.rooms?.join?[roomId]?.timeline?.limited ?? false,
            )
            .listen((_) => _gaps.add(null)),
      );
    final room = client.getRoomById(roomId);
    if (room != null) {
      _subs.add(room.onSessionKeyReceived.stream.listen(_onSessionKey));
    }
  }

  Future<void> _stop() async {
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
    for (final timer in _keyTimers.values) {
      timer.cancel();
    }
    _keyTimers.clear();
    _undecrypted.clear();
  }

  void _onTimelineEvent(Event e) {
    if (e.type != EventTypes.Encrypted) {
      _emit(e);
      return;
    }
    // Schlüssel fehlt (noch). Das SDK fordert ihn an; das Ereignis selbst
    // meldet es aber nicht erneut, wenn er eintrifft.
    final sessionId = e.content['session_id'];
    if (sessionId is! String) return;
    _undecrypted.putIfAbsent(sessionId, () => []).add(e);
    _keyTimers[sessionId] ??= Timer(keyTimeout, () {
      _keyTimers.remove(sessionId);
      if (_undecrypted.remove(sessionId) != null) _gaps.add(null);
    });
  }

  Future<void> _onSessionKey(String sessionId) async {
    final pending = _undecrypted.remove(sessionId);
    if (pending == null) return;
    _keyTimers.remove(sessionId)?.cancel();
    final encryption = client.encryption;
    if (encryption == null) return;
    for (final e in pending) {
      final decrypted = await encryption.decryptRoomEvent(e);
      if (decrypted.type == EventTypes.Encrypted) continue;
      _emit(decrypted);
    }
  }

  void _emit(Event e) {
    if (_events.isClosed) return;
    _events.add(
      RoomEvent(
        type: e.type,
        senderId: e.senderId,
        content: e.content,
        stateKey: e.stateKey,
      ),
    );
  }

  @override
  Future<void> send(String type, Map<String, Object?> content) async {
    final id = await _room.sendEvent(
      content,
      type: type,
      displayPendingEvent: false,
    );
    if (id == null) throw StateError('Senden fehlgeschlagen');
  }

  @override
  Map<String, Object?>? accountData(String type) =>
      client.getRoomById(roomId)?.roomAccountData[type]?.content;

  @override
  Stream<(String, Map<String, Object?>)> get accountDataUpdates =>
      client.onSync.stream.expand(
        (sync) => [
          for (final e
              in sync.rooms?.join?[roomId]?.accountData ?? const <BasicEvent>[])
            (e.type, e.content),
        ],
      );

  @override
  Future<void> setAccountData(String type, Map<String, Object?> content) =>
      client.setAccountDataPerRoom(userId, roomId, type, content);

  /// Der Client gehört der App und wird hier nicht geschlossen.
  @override
  Future<void> close() async {
    await _stop();
    await _events.close();
    await _gaps.close();
  }
}
