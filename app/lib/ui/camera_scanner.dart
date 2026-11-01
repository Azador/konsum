/// Kamera-Ansicht, die Barcodes erkennt. Android/iOS: zxing-cpp über
/// flutter_zxing; Browser: BarcodeDetector oder zxing-wasm.
library;

export 'camera_scanner_native.dart'
    if (dart.library.js_interop) 'camera_scanner_web.dart';
