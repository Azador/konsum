import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';

/// Kamerabild mit Barcode-Erkennung (zxing-cpp, ohne Google-Dienste).
/// [onCode] wird für jeden erkannten Code aufgerufen.
class CameraScanner extends StatelessWidget {
  const CameraScanner({super.key, required this.onCode});

  final void Function(String code) onCode;

  @override
  Widget build(BuildContext context) => ReaderWidget(
    onScan: (result) {
      final text = result.text;
      if (result.isValid && text != null && text.isNotEmpty) onCode(text);
    },
    codeFormat: Format.any,
    tryHarder: true,
    showGallery: false,
    showToggleCamera: false,
    // Strichcodes sind breit: einen größeren Ausschnitt auswerten.
    cropPercent: 0.8,
    scanDelay: const Duration(milliseconds: 200),
  );
}
