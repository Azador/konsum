import 'package:flutter/material.dart';

/// Text der Automatik für wiederkehrende Artikel: mit Symbol, kursiv und in
/// eigener Farbe, damit er sich von Eingetragenem unterscheidet.
InlineSpan autoSpan(BuildContext context, String text, [TextStyle? style]) {
  final color = style?.color ?? Theme.of(context).colorScheme.tertiary;
  return TextSpan(
    children: [
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(
          padding: const EdgeInsets.only(right: 2),
          child: Icon(Icons.autorenew, size: 14, color: color),
        ),
      ),
      TextSpan(text: text),
    ],
    style: TextStyle(fontStyle: FontStyle.italic, color: color),
  );
}
