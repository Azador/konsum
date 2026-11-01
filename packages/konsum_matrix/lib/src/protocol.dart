import 'dart:convert';

import 'package:konsum_core/konsum_core.dart';

/// Ereignistypen und Inhalte, mit denen Konsum Daten in Matrix-Räumen ablegt.
abstract final class KonsumEvents {
  /// Raumtyp im `m.room.create`-Ereignis, kennzeichnet Konsum-Gruppen.
  static const roomType = 'de.azadoro.konsum.group';

  /// Änderungen an den Gruppendaten (Timeline-Ereignis, verschlüsselt).
  static const changes = 'de.azadoro.konsum.changes';

  /// Bitte um den vollständigen Stand (neues Gerät oder neues Mitglied).
  static const snapshotRequest = 'de.azadoro.konsum.snapshot_request';

  /// Private Daten eines Benutzers (Room Account Data).
  static const private = 'de.azadoro.konsum.private';

  static const version = 1;

  /// Obergrenze für den JSON-Text eines Ereignisses. Matrix erlaubt 64 KiB
  /// pro Ereignis, Verschlüsselung (Base64) macht es ca. ein Drittel größer.
  static const maxChunkBytes = 24 * 1024;
}

/// Teilt Änderungen in Ereignis-Inhalte auf, die unter der Größengrenze bleiben.
List<Map<String, Object?>> encodeChanges(
  List<Change> changes, {
  required String device,
  bool snapshot = false,
  int maxBytes = KonsumEvents.maxChunkBytes,
}) {
  final result = <Map<String, Object?>>[];
  var chunk = <Map<String, Object?>>[];
  var size = 0;
  void flush() {
    if (chunk.isEmpty) return;
    result.add({
      'v': KonsumEvents.version,
      'device': device,
      'snapshot': ?(snapshot ? true : null),
      'changes': chunk,
    });
    chunk = [];
    size = 0;
  }

  for (final c in changes) {
    final json = c.toJson();
    final bytes = utf8.encode(jsonEncode(json)).length + 1;
    if (size + bytes > maxBytes) flush();
    chunk.add(json);
    size += bytes;
  }
  flush();
  return result;
}

/// Liest die Änderungen aus einem Ereignis-Inhalt. Unbekannte Versionen
/// oder kaputte Einträge werden übersprungen.
List<Change> decodeChanges(Map<String, Object?> content) {
  if (content['v'] != KonsumEvents.version) return const [];
  final list = content['changes'];
  if (list is! List) return const [];
  final result = <Change>[];
  for (final c in list) {
    try {
      result.add(Change.fromJson((c as Map).cast<String, Object?>()));
    } catch (_) {
      // Ein fehlerhafter Eintrag soll den Rest nicht verhindern.
    }
  }
  return result;
}
