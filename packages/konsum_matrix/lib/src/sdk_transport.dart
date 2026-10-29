import 'dart:async';

import 'package:matrix/matrix.dart';

import 'transport.dart';

/// [RoomTransport] über das Matrix-SDK. Das SDK übernimmt Sync,
/// Verschlüsselung und Wiederholungen beim Senden.
class SdkRoomTransport implements RoomTransport {
  SdkRoomTransport(this.client, this.roomId);

  final Client client;
  final String roomId;

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
  Stream<RoomEvent> get events => client.onTimelineEvent.stream
      .where((e) => e.roomId == roomId)
      .map(
        (e) => RoomEvent(
          type: e.type,
          senderId: e.senderId,
          content: e.content,
          stateKey: e.stateKey,
        ),
      );

  @override
  Stream<void> get gaps => client.onSync.stream.where(
    (sync) => sync.rooms?.join?[roomId]?.timeline?.limited ?? false,
  );

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
  Future<void> close() async {}
}
