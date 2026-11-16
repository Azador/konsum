import 'dart:math' as math;
import 'dart:typed_data';

/// Graustufenbild, eine Zeile nach der anderen, ein Byte je Pixel.
class GrayImage {
  GrayImage(this.width, this.height, this.pixels)
    : assert(pixels.length == width * height);

  final int width;
  final int height;
  final Uint8List pixels;

  /// Als PGM (P5) für Tesseract unter Linux.
  Uint8List toPgm() {
    final header = 'P5\n$width $height\n255\n'.codeUnits;
    return Uint8List(header.length + pixels.length)
      ..setAll(0, header)
      ..setAll(header.length, pixels);
  }
}

/// Eine Vorbereitung des Fotos für einen Tesseract-Lauf.
class OcrVariant {
  const OcrVariant(
    this.name, {
    this.width,
    this.binarize = false,
    this.psm = 6,
  });

  final String name;

  /// Breite des Bonausschnitts; null: ganzes Foto auf halber Größe, ohne
  /// Ausschnitt und Ausgleich.
  final int? width;
  final bool binarize;

  /// Tesseract „page segmentation mode“: 6 = ein Textblock, 4 = Spalte.
  final int psm;
}

/// Die Läufe des Prototyps (test-privat/prototyp): Jeder irrt sich an anderen
/// Stellen, zusammen ergaben sie bei allen Testbons jeden Preis.
const ocrVariants = [
  OcrVariant('1200', width: 1200),
  OcrVariant('1200b', width: 1200, binarize: true),
  OcrVariant('1400b', width: 1400, binarize: true),
  OcrVariant('1600', width: 1600),
  OcrVariant('1600b', width: 1600, binarize: true),
  OcrVariant('1400b-psm4', width: 1400, binarize: true, psm: 4),
  OcrVariant('ganz'),
];

/// Foto eines Bons, aufbereitet für die Texterkennung.
class ReceiptPhoto {
  ReceiptPhoto._(this._gray, this._paper, this.width, this.height);

  /// Aus RGBA-Pixeln (wie `ui.Image.toByteData(rawRgba)`).
  factory ReceiptPhoto.fromRgba(Uint8List rgba, int width, int height) {
    final n = width * height;
    final gray = Uint8List(n);
    final paper = Uint8List(n);
    for (var i = 0, p = 0; i < n; i++, p += 4) {
      final r = rgba[p], g = rgba[p + 1], b = rgba[p + 2];
      gray[i] = (r * 299 + g * 587 + b * 114) ~/ 1000;
      final mx = math.max(r, math.max(g, b));
      final mn = math.min(r, math.min(g, b));
      // Papier: hell und ungesättigt (Holz, Tischplatten sind gesättigt).
      final sat = mx == 0 ? 0 : (mx - mn) * 255 ~/ mx;
      paper[i] = sat < 70 && mx > 110 ? 1 : 0;
    }
    return ReceiptPhoto._(gray, paper, width, height);
  }

  final Uint8List _gray;
  final Uint8List _paper;
  final int width;
  final int height;

  /// Um 90° · [quarterTurns] im Uhrzeigersinn gedreht.
  ReceiptPhoto rotated(int quarterTurns) {
    final q = quarterTurns % 4;
    if (q == 0) return this;
    final w = q.isOdd ? height : width;
    final h = q.isOdd ? width : height;
    final g = Uint8List(w * h);
    final p = Uint8List(w * h);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final (nx, ny) = switch (q) {
          1 => (height - 1 - y, x),
          2 => (width - 1 - x, height - 1 - y),
          _ => (y, width - 1 - x),
        };
        final s = y * width + x, d = ny * w + nx;
        g[d] = _gray[s];
        p[d] = _paper[s];
      }
    }
    return ReceiptPhoto._(g, p, w, h);
  }

  /// Ausschnitt mit dem Papier: Spalten und Zeilen, die zu mindestens 30 %
  /// Papier sind.
  late final ({int x0, int y0, int x1, int y1}) paperBox = () {
    final cols = Int32List(width), rows = Int32List(height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        if (_paper[y * width + x] == 1) {
          cols[x]++;
          rows[y]++;
        }
      }
    }
    int first(Int32List a, int limit) {
      for (var i = 0; i < a.length; i++) {
        if (a[i] > limit) return i;
      }
      return 0;
    }

    int last(Int32List a, int limit) {
      for (var i = a.length - 1; i >= 0; i--) {
        if (a[i] > limit) return i + 1;
      }
      return a.length;
    }

    final cl = (height * 0.3).round(), rl = (width * 0.3).round();
    var box = (
      x0: first(cols, cl),
      y0: first(rows, rl),
      x1: last(cols, cl),
      y1: last(rows, rl),
    );
    if (box.x1 - box.x0 < width ~/ 10 || box.y1 - box.y0 < height ~/ 10) {
      box = (x0: 0, y0: 0, x1: width, y1: height); // kein Papier gefunden
    }
    return box;
  }();

  /// Liegt der Bon quer im Bild? Bons sind hoch und schmal.
  bool get sideways {
    final b = paperBox;
    return (b.x1 - b.x0) > (b.y1 - b.y0) * 1.15;
  }

  GrayImage prepare(OcrVariant v) {
    final w = v.width;
    if (w == null) {
      return _resize(_gray, width, height, 0, 0, width, height, width ~/ 2);
    }
    final b = paperBox;
    final g = _resize(_gray, width, height, b.x0, b.y0, b.x1, b.y1, w);
    return _normalize(g, binarize: v.binarize);
  }
}

/// Ausschnitt (x0, y0)–(x1, y1) von [src] auf Breite [dw] skaliert
/// (Flächenmittel beim Verkleinern, bilinear beim Vergrößern).
GrayImage _resize(
  Uint8List src,
  int sw,
  int sh,
  int x0,
  int y0,
  int x1,
  int y1,
  int dw,
) {
  final cw = x1 - x0, ch = y1 - y0;
  final dh = math.max(1, (ch * dw / cw).round());
  // Erst waagrecht, dann senkrecht.
  final tmp = Float32List(dw * ch);
  final hx = _weights(cw, dw);
  for (var y = 0; y < ch; y++) {
    final row = (y0 + y) * sw + x0;
    for (var x = 0; x < dw; x++) {
      final (start, ws) = hx[x];
      var acc = 0.0;
      for (var k = 0; k < ws.length; k++) {
        acc += src[row + start + k] * ws[k];
      }
      tmp[y * dw + x] = acc;
    }
  }
  final out = Uint8List(dw * dh);
  final vy = _weights(ch, dh);
  for (var y = 0; y < dh; y++) {
    final (start, ws) = vy[y];
    for (var x = 0; x < dw; x++) {
      var acc = 0.0;
      for (var k = 0; k < ws.length; k++) {
        acc += tmp[(start + k) * dw + x] * ws[k];
      }
      out[y * dw + x] = acc.round().clamp(0, 255);
    }
  }
  return GrayImage(dw, dh, out);
}

/// Gewichte je Zielpixel: (erstes Quellpixel, Gewichte).
List<(int, Float32List)> _weights(int n, int m) {
  final scale = n / m;
  final support = math.max(1.0, scale); // Dreiecksfilter
  return [
    for (var i = 0; i < m; i++)
      () {
        final center = (i + 0.5) * scale - 0.5;
        final a = math.max(0, (center - support).ceil());
        final b = math.min(n - 1, (center + support).floor());
        final ws = Float32List(b - a + 1);
        var sum = 0.0;
        for (var j = a; j <= b; j++) {
          final w = math.max(0.0, 1 - (j - center).abs() / support);
          ws[j - a] = w;
          sum += w;
        }
        if (sum == 0) {
          ws[(center.round() - a).clamp(0, ws.length - 1)] = 1;
        } else {
          for (var k = 0; k < ws.length; k++) {
            ws[k] /= sum;
          }
        }
        return (a, ws);
      }(),
  ];
}

/// Ausleuchtung ausgleichen: durch den geschätzten Papierhintergrund teilen
/// (Maximum, dann Minimum über ein Fenster breiter als jeder Strich, dann
/// geglättet), optional mit Otsu-Schwelle schwarzweiß.
GrayImage _normalize(GrayImage img, {required bool binarize}) {
  final w = img.width, h = img.height;
  final k = math.max(3, w ~/ 40) | 1;
  var bg = Float32List.fromList([for (final p in img.pixels) p.toDouble()]);
  bg = _rankFilter(bg, w, h, k, max: true);
  bg = _rankFilter(bg, w, h, k, max: false);
  bg = _gaussian(bg, w, h, k ~/ 2);
  final ratio = Float32List(w * h);
  for (var i = 0; i < ratio.length; i++) {
    ratio[i] = (img.pixels[i] / math.max(bg[i], 1)).clamp(0.0, 1.0);
  }
  final out = Uint8List(w * h);
  if (binarize) {
    final t = _otsu(ratio);
    for (var i = 0; i < out.length; i++) {
      out[i] = ratio[i] > t ? 255 : 0;
    }
  } else {
    for (var i = 0; i < out.length; i++) {
      out[i] = (ratio[i] * 255).round();
    }
  }
  return GrayImage(w, h, out);
}

/// Maximum- bzw. Minimumfilter mit quadratischem Fenster [k], getrennt nach
/// Zeilen und Spalten (van Herk/Gil-Werman, unabhängig von [k] linear).
Float32List _rankFilter(
  Float32List src,
  int w,
  int h,
  int k, {
  required bool max,
}) {
  final pick = max ? math.max<double> : math.min<double>;
  Float32List pass(Float32List s, int len, int lines, int step, int stride) {
    final out = Float32List(s.length);
    final r = k ~/ 2;
    final g = Float32List(len + k), hh = Float32List(len + k);
    final fill = max ? double.negativeInfinity : double.infinity;
    final line = Float32List(len + 2 * r);
    for (var l = 0; l < lines; l++) {
      final base = l * stride;
      for (var i = 0; i < line.length; i++) {
        final j = i - r;
        line[i] = j < 0 || j >= len ? fill : s[base + j * step];
      }
      final n = line.length;
      for (var i = 0; i < n; i++) {
        g[i] = i % k == 0 ? line[i] : pick(g[i - 1], line[i]);
      }
      for (var i = n - 1; i >= 0; i--) {
        hh[i] = (i == n - 1 || (i + 1) % k == 0)
            ? line[i]
            : pick(hh[i + 1], line[i]);
      }
      for (var j = 0; j < len; j++) {
        // Fenster line[j .. j+k-1]
        out[base + j * step] = pick(hh[j], g[j + k - 1]);
      }
    }
    return out;
  }

  final rows = pass(src, w, h, 1, w);
  return pass(rows, h, w, w, 1);
}

/// Näherung einer Gauß-Glättung mit Radius [sigma] durch drei Boxfilter.
Float32List _gaussian(Float32List src, int w, int h, int sigma) {
  if (sigma < 1) return src;
  final r = math.max(1, (math.sqrt(12 * sigma * sigma / 3 + 1) / 2).floor());
  var a = src;
  for (var i = 0; i < 3; i++) {
    a = _box(a, w, h, r);
  }
  return a;
}

Float32List _box(Float32List src, int w, int h, int r) {
  Float32List pass(Float32List s, int len, int lines, int step, int stride) {
    final out = Float32List(s.length);
    for (var l = 0; l < lines; l++) {
      final base = l * stride;
      var acc = 0.0;
      var count = 0;
      for (var j = 0; j < math.min(r, len); j++) {
        acc += s[base + j * step];
        count++;
      }
      for (var j = 0; j < len; j++) {
        final add = j + r;
        if (add < len) {
          acc += s[base + add * step];
          count++;
        }
        final rem = j - r - 1;
        if (rem >= 0) {
          acc -= s[base + rem * step];
          count--;
        }
        out[base + j * step] = acc / count;
      }
    }
    return out;
  }

  return pass(pass(src, w, h, 1, w), h, w, w, 1);
}

double _otsu(Float32List a) {
  final hist = Int32List(256);
  for (final v in a) {
    hist[(v * 255).round().clamp(0, 255)]++;
  }
  final total = a.length;
  var sumAll = 0.0;
  for (var i = 0; i < 256; i++) {
    sumAll += i * hist[i];
  }
  var wB = 0, sumB = 0.0, best = 0.0, t = 0;
  for (var i = 0; i < 256; i++) {
    wB += hist[i];
    if (wB == 0) continue;
    final wF = total - wB;
    if (wF == 0) break;
    sumB += i * hist[i];
    final mB = sumB / wB, mF = (sumAll - sumB) / wF;
    final between = wB * wF * (mB - mF) * (mB - mF);
    if (between > best) {
      best = between;
      t = i;
    }
  }
  return t / 255;
}
