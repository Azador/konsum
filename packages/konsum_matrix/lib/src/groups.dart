import 'package:matrix/matrix.dart';

import 'matrix_group_sync.dart';
import 'protocol.dart';
import 'sdk_transport.dart';

/// Eine Konsum-Gruppe als Matrix-Raum, aus Sicht eines angemeldeten Kontos.
class MatrixGroupRef {
  const MatrixGroupRef({
    required this.roomId,
    required this.name,
    required this.invited,
  });

  final String roomId;
  final String name;

  /// true: Einladung, noch nicht beigetreten.
  final bool invited;
}

/// Verwaltung der Konsum-Gruppen eines Matrix-Kontos.
class MatrixGroups {
  MatrixGroups(this.client);

  final Client client;

  /// Die Ereignistypen des Raums, null wenn er keine Konsum-Gruppe ist.
  static KonsumEventNames? namesOf(Room room) => KonsumEventNames.forRoomType(
    room.getState(EventTypes.RoomCreate)?.content['type'],
  );

  static bool isKonsumRoom(Room room) => namesOf(room) != null;

  /// Konsum-Räume, in denen das Konto Mitglied oder eingeladen ist.
  List<MatrixGroupRef> get groups => [
    for (final room in client.rooms)
      if (isKonsumRoom(room) &&
          (room.membership == Membership.join ||
              room.membership == Membership.invite))
        MatrixGroupRef(
          roomId: room.id,
          name: room.getLocalizedDisplayname(),
          invited: room.membership == Membership.invite,
        ),
  ];

  /// Legt eine neue Gruppe an. Verschlüsselt, wenn der Client Verschlüsselung
  /// unterstützt; nur eingeladene Personen können beitreten.
  Future<String> create(String name, {List<String> invite = const []}) async {
    final roomId = await client.createRoom(
      name: name,
      preset: CreateRoomPreset.privateChat,
      creationContent: {'type': KonsumEvents.roomType},
      invite: invite,
      initialState: [
        if (client.encryptionEnabled)
          StateEvent(
            type: EventTypes.Encryption,
            content: {'algorithm': AlgorithmTypes.megolmV1AesSha2},
          ),
        StateEvent(
          type: EventTypes.HistoryVisibility,
          content: {'history_visibility': HistoryVisibility.shared.text},
        ),
      ],
    );
    if (client.getRoomById(roomId) == null) {
      await client.waitForRoomInSync(roomId, join: true);
    }
    return roomId;
  }

  Future<void> invite(String roomId, String userId) =>
      client.getRoomById(roomId)!.invite(userId);

  Future<void> join(String roomId) => client.getRoomById(roomId)!.join();

  Future<void> leave(String roomId) => client.getRoomById(roomId)!.leave();

  Future<void> rename(String roomId, String name) =>
      client.getRoomById(roomId)!.setName(name);

  /// Mitglieder (Matrix-IDs) einer Gruppe, die beigetreten oder eingeladen sind.
  Future<List<String>> members(String roomId) async {
    final users = await client.getRoomById(roomId)!.requestParticipants([
      Membership.join,
      Membership.invite,
    ]);
    return [for (final u in users) u.id];
  }

  /// Verbindung für die Synchronisation der Gruppe.
  MatrixGroupSync sync(String roomId) {
    final room = client.getRoomById(roomId);
    return MatrixGroupSync(
      SdkRoomTransport(client, roomId),
      names: (room == null ? null : namesOf(room)) ?? KonsumEventNames.current,
    );
  }
}
