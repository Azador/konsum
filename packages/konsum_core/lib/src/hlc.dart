import 'dart:math' as math;

/// Hybrid Logical Clock: Zeitstempel, die über Geräte hinweg total geordnet
/// sind, auch wenn deren Uhren leicht voneinander abweichen.
///
/// Ordnung: Millisekunden, dann Zähler, dann Knoten-ID (Gerät).
class Hlc implements Comparable<Hlc> {
  const Hlc(this.millis, this.counter, this.node);

  const Hlc.zero(String node) : this(0, 0, node);

  final int millis;
  final int counter;
  final String node;

  /// Zeitstempel für ein lokales Ereignis.
  Hlc send(int now) {
    final m = math.max(millis, now);
    return Hlc(m, m == millis ? counter + 1 : 0, node);
  }

  /// Zeitstempel nach Empfang eines entfernten Ereignisses.
  Hlc receive(Hlc remote, int now) {
    final m = math.max(now, math.max(millis, remote.millis));
    final int c;
    if (m == millis && m == remote.millis) {
      c = math.max(counter, remote.counter) + 1;
    } else if (m == millis) {
      c = counter + 1;
    } else if (m == remote.millis) {
      c = remote.counter + 1;
    } else {
      c = 0;
    }
    return Hlc(m, c, node);
  }

  @override
  int compareTo(Hlc other) {
    if (millis != other.millis) return millis.compareTo(other.millis);
    if (counter != other.counter) return counter.compareTo(other.counter);
    return node.compareTo(other.node);
  }

  bool operator >(Hlc other) => compareTo(other) > 0;
  bool operator <(Hlc other) => compareTo(other) < 0;

  @override
  bool operator ==(Object other) =>
      other is Hlc &&
      other.millis == millis &&
      other.counter == counter &&
      other.node == node;

  @override
  int get hashCode => Object.hash(millis, counter, node);

  /// Textform `millis-counter-node`, z. B. `1761700000000-0-a1b2`.
  @override
  String toString() => '$millis-$counter-$node';

  static Hlc parse(String s) {
    final first = s.indexOf('-');
    final second = s.indexOf('-', first + 1);
    if (first < 0 || second < 0) throw FormatException('Ungültiger HLC', s);
    return Hlc(
      int.parse(s.substring(0, first)),
      int.parse(s.substring(first + 1, second)),
      s.substring(second + 1),
    );
  }
}

/// Uhr eines Geräts, die fortlaufend [Hlc]-Zeitstempel vergibt.
class HlcClock {
  HlcClock(String node, {int Function()? now})
    : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch),
      _last = Hlc.zero(node);

  final int Function() _now;
  Hlc _last;

  String get node => _last.node;

  Hlc tick() => _last = _last.send(_now());

  void observe(Hlc remote) => _last = _last.receive(remote, _now());
}
