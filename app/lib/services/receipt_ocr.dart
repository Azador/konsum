import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:konsum_core/konsum_core.dart';

import 'receipt_image.dart';

/// Kassenbons lesen gibt es auf Android (Tesseract4Android) und unter Linux
/// (Tesseract aus dem System, Paket `tesseract-ocr`).
bool get receiptScanAvailable =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.linux);

/// Texterkennung eines Graustufenbilds.
abstract interface class OcrEngine {
  Future<String> recognize(GrayImage image, {required int psm});

  /// Wie viele Läufe gleichzeitig sinnvoll sind.
  int get parallel;

  /// Ob die Texterkennung auf diesem Gerät läuft (unter Linux: ob das
  /// Programm `tesseract` installiert ist).
  Future<bool> available();

  static OcrEngine forPlatform() =>
      Platform.isAndroid ? _AndroidOcr() : _TesseractProcess();
}

class OcrException implements Exception {
  OcrException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Tesseract4Android über einen Kanal zu MainActivity (OcrChannel.kt).
class _AndroidOcr implements OcrEngine {
  static const _channel = MethodChannel('de.azadoro.konsum/ocr');

  @override
  int get parallel =>
      math.max(1, math.min(4, Platform.numberOfProcessors ~/ 2));

  @override
  Future<bool> available() async => true;

  @override
  Future<String> recognize(GrayImage image, {required int psm}) async {
    try {
      final text = await _channel.invokeMethod<String>('recognize', {
        'pixels': image.pixels,
        'width': image.width,
        'height': image.height,
        'psm': psm,
      });
      return text ?? '';
    } on PlatformException catch (e) {
      throw OcrException('Texterkennung fehlgeschlagen: ${e.message}');
    }
  }
}

/// `tesseract` als eigener Prozess; das Bild geht als PGM über stdin.
class _TesseractProcess implements OcrEngine {
  @override
  int get parallel => math.max(1, math.min(8, Platform.numberOfProcessors - 1));

  @override
  Future<bool> available() async {
    try {
      final r = await Process.run('tesseract', ['--version']);
      return r.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  /// Das mitgelieferte Modell, damit überall dasselbe gilt; sonst das des
  /// Systems (Paket `tesseract-ocr-deu`).
  static final String? _tessdata = () {
    final dir =
        '${File(Platform.resolvedExecutable).parent.path}'
        '/data/flutter_assets/assets/tessdata';
    return File('$dir/deu.traineddata').existsSync() ? dir : null;
  }();

  @override
  Future<String> recognize(GrayImage image, {required int psm}) async {
    final Process p;
    try {
      p = await Process.start(
        'tesseract',
        [
          'stdin',
          'stdout',
          '-l',
          'deu',
          '--psm',
          '$psm',
          if (_tessdata case final dir?) ...['--tessdata-dir', dir],
        ],
        // Jeder Lauf auf einem Kern; parallel laufen mehrere.
        environment: {'OMP_THREAD_LIMIT': '1'},
      );
    } on ProcessException {
      throw OcrException(
        'Tesseract fehlt – bitte das Paket „tesseract-ocr“ installieren',
      );
    }
    final out = p.stdout.transform(const SystemEncoding().decoder).join();
    final err = p.stderr.transform(const SystemEncoding().decoder).join();
    p.stdin.add(image.toPgm());
    await p.stdin.close();
    final code = await p.exitCode;
    if (code != 0) {
      throw OcrException('Tesseract: ${(await err).trim()}');
    }
    return out;
  }
}

/// Fortschritt beim Lesen: erledigte und gesamte Läufe.
typedef OcrProgress = void Function(int done, int total);

/// Liest einen Bon aus einem Foto (JPEG/PNG). [quarterTurns] dreht das Foto
/// zusätzlich (im Uhrzeigersinn); ohne Angabe wird die Lage geschätzt.
Future<({Receipt receipt, int quarterTurns})> readReceiptPhoto(
  Uint8List bytes, {
  OcrEngine? engine,
  int? quarterTurns,
  OcrProgress? onProgress,
}) async {
  final ocr = engine ?? OcrEngine.forPlatform();
  final rgba = await _decode(bytes);
  final photo = await _fromRgba(rgba.pixels, rgba.width, rgba.height);

  var turns = quarterTurns;
  if (turns == null) {
    // Quer liegender Bon: beide Richtungen kurz probieren.
    turns = 0;
    if (await _sideways(photo)) {
      const probe = OcrVariant('probe', width: 1200, binarize: true);
      final scores = await Future.wait([
        for (final t in const [1, 3])
          _prepare(
            photo,
            probe,
            turns: t,
          ).then((img) => ocr.recognize(img, psm: 6)).then(_plausibility),
      ]);
      turns = scores[0] >= scores[1] ? 1 : 3;
    }
  }
  final t = turns;
  final upright = await _rotate(photo, t);

  final total = ocrVariants.length;
  var done = 0;
  onProgress?.call(0, total);
  final texts = List<String>.filled(total, '');
  var next = 0;
  Future<void> worker() async {
    while (next < total) {
      final i = next++;
      final v = ocrVariants[i];
      final img = await _prepare(upright, v);
      texts[i] = await ocr.recognize(img, psm: v.psm);
      onProgress?.call(++done, total);
    }
  }

  await Future.wait([for (var i = 0; i < ocr.parallel; i++) worker()]);
  return (receipt: readReceipt(texts), quarterTurns: t);
}

// Isolate-Aufrufe als eigene Funktionen: Eine Closure nimmt ihren ganzen
// Kontext mit ins Isolate, hier also nur die Parameter.

Future<ReceiptPhoto> _fromRgba(Uint8List rgba, int w, int h) =>
    Isolate.run(() => ReceiptPhoto.fromRgba(rgba, w, h));

Future<bool> _sideways(ReceiptPhoto p) => Isolate.run(() => p.sideways);

Future<ReceiptPhoto> _rotate(ReceiptPhoto p, int turns) =>
    Isolate.run(() => p.rotated(turns));

Future<GrayImage> _prepare(ReceiptPhoto p, OcrVariant v, {int turns = 0}) =>
    Isolate.run(() => p.rotated(turns).prepare(v));

/// Wie sehr ein OCR-Text nach Bon aussieht: Zeilen mit Preis am Ende.
int _plausibility(String text) => RegExp(
  r'\d+[,.]\d\d\s*\S{0,3}\s*$',
  multiLine: true,
).allMatches(text).length;

Future<({Uint8List pixels, int width, int height})> _decode(
  Uint8List bytes,
) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final result = (
    pixels: data!.buffer.asUint8List(),
    width: image.width,
    height: image.height,
  );
  image.dispose();
  codec.dispose();
  return result;
}
