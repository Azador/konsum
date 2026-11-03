import 'package:flutter/material.dart';

import 'theme.dart';

/// Name der Farbe für die Anzeige in den Einstellungen.
String seedName(int? argb) {
  if (argb == null) return 'Grün (Standard)';
  for (final (name, color) in seedPresets) {
    if (color.toARGB32() == argb) return name;
  }
  return 'Eigene Farbe';
}

/// Lässt eine Farbe fürs Farbschema wählen. Liefert den ARGB-Wert (`null`
/// für den Standard) oder bei Abbruch `null` statt des Records.
Future<(int?,)?> pickSeed(BuildContext context, int? current) =>
    showDialog<(int?,)>(context: context, builder: (_) => _SeedDialog(current));

class _SeedDialog extends StatefulWidget {
  const _SeedDialog(this.current);

  final int? current;

  @override
  State<_SeedDialog> createState() => _SeedDialogState();
}

class _SeedDialogState extends State<_SeedDialog> {
  late int _argb = widget.current ?? defaultSeed.toARGB32();
  late double _hue = HSVColor.fromColor(Color(_argb)).hue;

  bool get _isPreset => seedPresets.any((p) => p.$2.toARGB32() == _argb);

  /// Die Primärfarbe, die das Schema aus [seed] tatsächlich ergibt.
  Color _primary(Color seed) =>
      buildTheme(seed, Theme.of(context).brightness).colorScheme.primary;

  Widget _swatch(Color seed, {required bool selected, required String label}) {
    final primary = _primary(seed);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: primary,
            shape: BoxShape.circle,
            border: selected
                ? Border.all(
                    color: Theme.of(context).colorScheme.onSurface,
                    width: 3,
                  )
                : null,
          ),
          child: selected
              ? Icon(
                  Icons.check,
                  color:
                      ThemeData.estimateBrightnessForColor(primary) ==
                          Brightness.dark
                      ? Colors.white
                      : Colors.black,
                )
              : null,
        ),
        const SizedBox(height: 4),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final custom = HSVColor.fromAHSV(1, _hue, 0.7, 0.75).toColor();
    return AlertDialog(
      title: const Text('Farbschema'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final (name, color) in seedPresets)
                InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => setState(() {
                    _argb = color.toARGB32();
                    if (color != Colors.grey) {
                      _hue = HSVColor.fromColor(color).hue;
                    }
                  }),
                  child: _swatch(
                    color,
                    selected: _argb == color.toARGB32(),
                    label: name,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _swatch(custom, selected: !_isPreset, label: 'Eigene'),
              const SizedBox(width: 12),
              Expanded(
                child: _HueSlider(
                  hue: _hue,
                  onChanged: (h) => setState(() {
                    _hue = h;
                    _argb = HSVColor.fromAHSV(
                      1,
                      h,
                      0.7,
                      0.75,
                    ).toColor().toARGB32();
                  }),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, (
            _argb == defaultSeed.toARGB32() ? null : _argb,
          )),
          child: const Text('Übernehmen'),
        ),
      ],
    );
  }
}

/// Schieberegler über alle Farbtöne.
class _HueSlider extends StatelessWidget {
  const _HueSlider({required this.hue, required this.onChanged});

  final double hue;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.center,
    children: [
      Container(
        height: 12,
        margin: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          gradient: LinearGradient(
            colors: [
              for (var h = 0; h <= 360; h += 30)
                HSVColor.fromAHSV(1, h.toDouble(), 0.7, 0.85).toColor(),
            ],
          ),
        ),
      ),
      SliderTheme(
        data: SliderTheme.of(context).copyWith(
          activeTrackColor: Colors.transparent,
          inactiveTrackColor: Colors.transparent,
          thumbColor: HSVColor.fromAHSV(1, hue, 0.7, 0.85).toColor(),
        ),
        child: Slider(value: hue, max: 360, onChanged: onChanged),
      ),
    ],
  );
}
