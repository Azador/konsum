import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// Kamerabild mit Barcode-Erkennung im Browser.
///
/// Nimmt den eingebauten `BarcodeDetector` (Chrome, Edge, Android), sonst
/// zxing-wasm (Firefox, Safari). zxing-wasm liegt unter `zxing/` neben der
/// App (deploy/web/fetch-zxing.sh), damit nichts von einem CDN geladen wird.
class CameraScanner extends StatefulWidget {
  const CameraScanner({super.key, required this.onCode});

  final void Function(String code) onCode;

  @override
  State<CameraScanner> createState() => _CameraScannerState();
}

class _CameraScannerState extends State<CameraScanner> {
  static var _nextId = 0;

  late final String _viewType = 'konsum-camera-${_nextId++}';
  final _video = web.HTMLVideoElement();
  web.MediaStream? _stream;
  Timer? _timer;
  _Decoder? _decoder;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _video
      ..autoplay = true
      ..muted = true
      ..setAttribute('playsinline', 'true')
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'cover';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (_) => _video);
    _start();
  }

  Future<void> _start() async {
    try {
      final stream = await web.window.navigator.mediaDevices
          .getUserMedia(
            web.MediaStreamConstraints(
              video: {
                'facingMode': {'ideal': 'environment'},
                'width': {'ideal': 1280},
              }.jsify()!,
            ),
          )
          .toDart;
      if (!mounted) {
        _stopTracks(stream);
        return;
      }
      _stream = stream;
      _video.srcObject = stream;
      _decoder = await _Decoder.create();
      if (!mounted) return;
      _timer = Timer.periodic(
        const Duration(milliseconds: 250),
        (_) => _tick(),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Kamera nicht verfügbar. Barcode eintippen?');
      }
    }
  }

  Future<void> _tick() async {
    final decoder = _decoder;
    if (_busy || decoder == null || _video.readyState < 2) return;
    _busy = true;
    try {
      final code = await decoder.decode(_video);
      if (code != null && mounted) widget.onCode(code);
    } catch (_) {
      // Einzelnes Bild nicht lesbar: beim nächsten weiter.
    } finally {
      _busy = false;
    }
  }

  static void _stopTracks(web.MediaStream stream) {
    for (final track in stream.getTracks().toDart) {
      track.stop();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    final stream = _stream;
    if (stream != null) _stopTracks(stream);
    _video.srcObject = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(error, textAlign: TextAlign.center),
        ),
      );
    }
    return HtmlElementView(viewType: _viewType);
  }
}

/// Erkennt Barcodes in einem Videobild.
abstract class _Decoder {
  static Future<_Decoder> create() async {
    if (await _NativeDecoder.supported()) return _NativeDecoder();
    return _ZxingDecoder.create();
  }

  Future<String?> decode(web.HTMLVideoElement video);
}

@JS('BarcodeDetector')
extension type _BarcodeDetector._(JSObject _) implements JSObject {
  external factory _BarcodeDetector();
  external static JSPromise<JSArray<JSString>> getSupportedFormats();
  external JSPromise<JSArray<_Detected>> detect(web.HTMLVideoElement video);
}

extension type _Detected._(JSObject _) implements JSObject {
  external String get rawValue;
}

class _NativeDecoder implements _Decoder {
  final _detector = _BarcodeDetector();

  static Future<bool> supported() async {
    try {
      final formats = await _BarcodeDetector.getSupportedFormats().toDart;
      return formats.toDart.isNotEmpty;
    } catch (_) {
      return false; // BarcodeDetector fehlt
    }
  }

  @override
  Future<String?> decode(web.HTMLVideoElement video) async {
    final found = await _detector.detect(video).toDart;
    for (final b in found.toDart) {
      if (b.rawValue.isNotEmpty) return b.rawValue;
    }
    return null;
  }
}

@JS('ZXingWASM')
external _ZxingWasm? get _zxingWasm;

extension type _ZxingWasm._(JSObject _) implements JSObject {
  external JSAny? prepareZXingModule(JSObject options);
  external JSPromise<JSArray<_ZxingResult>> readBarcodes(
    web.ImageData image,
    JSObject options,
  );
}

extension type _ZxingResult._(JSObject _) implements JSObject {
  external bool get isValid;
  external String get text;
}

class _ZxingDecoder implements _Decoder {
  _ZxingDecoder(this._zxing);

  final _ZxingWasm _zxing;
  final _canvas = web.HTMLCanvasElement();
  late final _ctx = _canvas.getContext(
    '2d',
    {'willReadFrequently': true}.jsify(),
  ) as web.CanvasRenderingContext2D;
  final _options =
      {'tryHarder': true, 'maxNumberOfSymbols': 1}.jsify()! as JSObject;

  static Future<_ZxingDecoder> create() async {
    var zxing = _zxingWasm;
    if (zxing == null) {
      final script = web.HTMLScriptElement()..src = 'zxing/index.js';
      final loaded = Completer<void>();
      script
        ..onload = ((web.Event _) => loaded.complete()).toJS
        ..onerror = ((web.Event _) => loaded.completeError(
          StateError('zxing/index.js fehlt'),
        )).toJS;
      web.document.head!.append(script);
      await loaded.future;
      zxing = _zxingWasm!;
    }
    // Die .wasm-Datei liegt neben index.js statt auf dem CDN.
    final overrides = JSObject()
      ..setProperty(
        'locateFile'.toJS,
        ((String path, String prefix) => 'zxing/$path').toJS,
      );
    zxing.prepareZXingModule(
      JSObject()..setProperty('overrides'.toJS, overrides),
    );
    return _ZxingDecoder(zxing);
  }

  @override
  Future<String?> decode(web.HTMLVideoElement video) async {
    final w = video.videoWidth, h = video.videoHeight;
    if (w == 0 || h == 0) return null;
    if (_canvas.width != w || _canvas.height != h) {
      _canvas
        ..width = w
        ..height = h;
    }
    _ctx.drawImage(video, 0, 0);
    final results = await _zxing
        .readBarcodes(_ctx.getImageData(0, 0, w, h), _options)
        .toDart;
    for (final r in results.toDart) {
      if (r.isValid && r.text.isNotEmpty) return r.text;
    }
    return null;
  }
}
