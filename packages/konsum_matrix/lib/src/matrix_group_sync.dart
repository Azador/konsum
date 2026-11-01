import 'dart:async';
import 'dart:math' as math;

import 'package:konsum_core/konsum_core.dart';

import 'protocol.dart';
import 'transport.dart';

/// Synchronisiert eine Gruppe über einen Matrix-Raum.
///
/// - Änderungen gehen als `de.azadoro.konsum.changes`-Ereignisse in den Raum.
/// - Neue Mitglieder und neue Geräte können ältere verschlüsselte Ereignisse
///   meist nicht entschlüsseln. Deshalb fragt ein Gerät ohne Daten nach dem
///   vollständigen Stand, und tritt jemand bei, schickt ein anderes Mitglied
///   ihn unaufgefordert. Damit nicht alle gleichzeitig antworten, wartet
///   jedes Gerät eine zufällige Zeit und antwortet nicht, wenn inzwischen
///   ein anderes geantwortet hat.
/// - Bleibt die Bitte unbeantwortet (kein anderes Gerät online), fragt ein
///   Gerät ohne Daten in wachsenden Abständen erneut ([retryDelay], bis
///   [maxRetryDelay]), bis Daten kommen.
/// - Hat der Server nach langer Offline-Zeit nicht alle Ereignisse geliefert
///   (Lücke), fragt das Gerät ebenfalls nach dem vollständigen Stand.
/// - Private Daten liegen in der Room Account Data des Benutzers.
class MatrixGroupSync implements GroupSync {
  MatrixGroupSync(
    this._transport, {
    math.Random? random,
    this.maxReplyDelay = const Duration(seconds: 3),
    this.retryDelay = const Duration(seconds: 30),
    this.maxRetryDelay = const Duration(minutes: 30),
  }) : _random = random ?? math.Random() {
    _subscriptions
      ..add(_transport.events.listen(_onEvent))
      ..add(_transport.gaps.listen((_) => _requestSnapshot()))
      ..add(
        _transport.accountDataUpdates.listen((update) {
          if (update.$1 == KonsumEvents.private) {
            _incomingPrivate.add(decodeChanges(update.$2));
          }
        }),
      );
  }

  final RoomTransport _transport;
  final math.Random _random;
  final Duration maxReplyDelay;
  final Duration retryDelay;
  final Duration maxRetryDelay;
  final _subscriptions = <StreamSubscription<Object?>>[];
  final _incoming = StreamController<List<Change>>.broadcast();
  final _incomingPrivate = StreamController<List<Change>>.broadcast();
  List<Change> Function() _snapshot = () => const [];
  Timer? _replyTimer;
  Timer? _retryTimer;
  bool _started = false;

  @override
  Stream<List<Change>> get incoming => _incoming.stream;

  @override
  Stream<List<Change>> get incomingPrivate => _incomingPrivate.stream;

  @override
  set snapshotProvider(List<Change> Function() provider) {
    _snapshot = provider;
    if (!_started) {
      _started = true;
      scheduleMicrotask(_start);
    }
  }

  /// Bei leerem lokalem Stand um den vollständigen Stand bitten und die
  /// bereits gespeicherten privaten Daten übernehmen.
  Future<void> _start() async {
    final private = _transport.accountData(KonsumEvents.private);
    if (private != null) _incomingPrivate.add(decodeChanges(private));
    if (_snapshot().isEmpty) {
      await _requestSnapshot();
      _scheduleRetry(retryDelay);
    }
  }

  /// Fragt erneut, solange der lokale Stand leer ist.
  void _scheduleRetry(Duration delay) {
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () async {
      _retryTimer = null;
      if (_snapshot().isNotEmpty) return;
      await _requestSnapshot();
      final next = delay * 2;
      _scheduleRetry(next > maxRetryDelay ? maxRetryDelay : next);
    });
  }

  Future<void> _requestSnapshot() async {
    try {
      await _transport.send(KonsumEvents.snapshotRequest, {
        'v': KonsumEvents.version,
        'device': _transport.deviceId,
      });
    } catch (_) {
      // Offline: Antworten kommen dann über einen späteren Beitritt
      // oder die nächste Anfrage.
    }
  }

  bool _isOwnDevice(RoomEvent e) =>
      e.senderId == _transport.userId &&
      e.content['device'] == _transport.deviceId;

  void _onEvent(RoomEvent e) {
    switch (e.type) {
      case KonsumEvents.changes:
        if (_isOwnDevice(e)) return;
        final changes = decodeChanges(e.content);
        if (changes.isNotEmpty) _incoming.add(changes);
        if (e.content['snapshot'] == true) _cancelReply();
      case KonsumEvents.snapshotRequest:
        if (!_isOwnDevice(e)) _scheduleReply();
      case 'm.room.member':
        if (e.content['membership'] == 'join' &&
            e.stateKey != null &&
            e.stateKey != _transport.userId) {
          _scheduleReply();
        }
    }
  }

  void _scheduleReply() {
    if (_replyTimer != null) return;
    final delay = Duration(
      milliseconds: _random.nextInt(maxReplyDelay.inMilliseconds + 1),
    );
    _replyTimer = Timer(delay, () async {
      _replyTimer = null;
      final snapshot = _snapshot();
      if (snapshot.isEmpty) return;
      try {
        await _sendChunks(snapshot, snapshot: true);
      } catch (_) {
        // Nicht schlimm: Ein anderes Mitglied oder eine erneute Anfrage
        // holt das nach.
      }
    });
  }

  void _cancelReply() {
    _replyTimer?.cancel();
    _replyTimer = null;
  }

  Future<void> _sendChunks(
    List<Change> changes, {
    bool snapshot = false,
  }) async {
    for (final content in encodeChanges(
      changes,
      device: _transport.deviceId,
      snapshot: snapshot,
    )) {
      await _transport.send(KonsumEvents.changes, content);
    }
  }

  @override
  Future<void> send(List<Change> changes) => _sendChunks(changes);

  @override
  Future<void> savePrivate(List<Change> snapshot) {
    final chunks = encodeChanges(
      snapshot,
      device: _transport.deviceId,
      maxBytes: 1 << 30,
    );
    return _transport.setAccountData(
      KonsumEvents.private,
      chunks.isEmpty
          ? {'v': KonsumEvents.version, 'changes': const <Object?>[]}
          : chunks.single,
    );
  }

  @override
  Future<void> close() async {
    _cancelReply();
    _retryTimer?.cancel();
    for (final s in _subscriptions) {
      await s.cancel();
    }
    await _transport.close();
    await _incoming.close();
    await _incomingPrivate.close();
  }
}
