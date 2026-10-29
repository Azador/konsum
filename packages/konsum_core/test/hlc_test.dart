import 'package:konsum_core/konsum_core.dart';
import 'package:test/test.dart';

void main() {
  test('Ordnung: Zeit, dann Zähler, dann Knoten', () {
    expect(const Hlc(2, 0, 'a') > const Hlc(1, 9, 'z'), isTrue);
    expect(const Hlc(1, 2, 'a') > const Hlc(1, 1, 'z'), isTrue);
    expect(const Hlc(1, 1, 'b') > const Hlc(1, 1, 'a'), isTrue);
  });

  test('Textform ist umkehrbar, auch mit Bindestrich im Knoten', () {
    const h = Hlc(1761700000000, 3, 'gerät-1');
    expect(Hlc.parse(h.toString()), h);
  });

  test('Uhr bleibt monoton, auch wenn die Systemzeit zurückspringt', () {
    var now = 1000;
    final clock = HlcClock('a', now: () => now);
    final first = clock.tick();
    now = 500;
    final second = clock.tick();
    expect(second > first, isTrue);
  });

  test('Nach Empfang liegt der eigene Zeitstempel hinter dem fremden', () {
    final clock = HlcClock('a', now: () => 1000);
    const remote = Hlc(5000, 7, 'b');
    clock.observe(remote);
    expect(clock.tick() > remote, isTrue);
  });
}
