/// Ein (entschlüsseltes) Timeline-Ereignis eines Raums.
class RoomEvent {
  const RoomEvent({
    required this.type,
    required this.senderId,
    required this.content,
    this.stateKey,
  });

  final String type;
  final String senderId;
  final Map<String, Object?> content;
  final String? stateKey;
}

/// Das, was [MatrixGroupSync] von einem Matrix-Raum braucht. Die echte
/// Umsetzung ist `SdkRoomTransport`; Tests verwenden eine Attrappe.
abstract interface class RoomTransport {
  String get userId;
  String get deviceId;

  /// Neue Timeline-Ereignisse des Raums (auch die eigenen).
  Stream<RoomEvent> get events;

  /// Meldet, wenn der Server nicht alle verpassten Ereignisse geliefert hat
  /// (Lücke in der Timeline, z. B. nach langer Offline-Zeit).
  Stream<void> get gaps;

  /// Verschickt ein Timeline-Ereignis. Wirft bei Fehlern.
  Future<void> send(String type, Map<String, Object?> content);

  /// Aktueller Inhalt der Room Account Data vom Typ [type], falls vorhanden.
  Map<String, Object?>? accountData(String type);

  /// Änderungen der Room Account Data (Typ, Inhalt).
  Stream<(String, Map<String, Object?>)> get accountDataUpdates;

  Future<void> setAccountData(String type, Map<String, Object?> content);

  Future<void> close();
}
