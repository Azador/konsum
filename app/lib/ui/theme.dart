import 'package:flutter/material.dart';

/// Farbe, wenn für eine Gruppe nichts gewählt ist.
const defaultSeed = Colors.green;

/// Vorgeschlagene Farben fürs Farbschema. Material 3 leitet daraus Paletten
/// mit gleicher Sättigung und Helligkeit ab, nur der Farbton zählt.
const seedPresets = <(String, Color)>[
  ('Grün', Colors.green),
  ('Blau', Colors.blue),
  ('Rot', Colors.red),
  ('Orange', Colors.orange),
  ('Violett', Colors.deepPurple),
  ('Grau', Colors.grey),
];

/// Ob [seed] praktisch farblos ist; dann wird ein graues Schema erzeugt statt
/// eines, das aus dem zufälligen Farbton eine kräftige Farbe macht.
bool _isGrey(Color seed) => HSVColor.fromColor(seed).saturation < 0.1;

ThemeData buildTheme(Color? seed, Brightness brightness) => ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: seed ?? defaultSeed,
    brightness: brightness,
    dynamicSchemeVariant: seed != null && _isGrey(seed)
        ? DynamicSchemeVariant.monochrome
        : DynamicSchemeVariant.tonalSpot,
  ),
  fontFamily: 'Roboto',
);
