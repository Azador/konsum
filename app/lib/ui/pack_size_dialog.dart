import 'package:flutter/material.dart';
import 'package:konsum_core/konsum_core.dart';

import 'format.dart';
import 'unit_field.dart';

/// Ergebnis von [showPackSizeDialog]; `size == null` heißt „keine“.
typedef PackSize = ({num? size, String unit});

/// Fragt eine Packungsgröße ab (Zahl und g/kg/ml/l/Stück). Null bei Abbruch.
Future<PackSize?> showPackSizeDialog(
  BuildContext context, {
  num? size,
  String? unit,
  String title = 'Packungsgröße',
}) => showDialog<PackSize>(
  context: context,
  builder: (_) => _PackSizeDialog(size: size, unit: unit, title: title),
);

class _PackSizeDialog extends StatefulWidget {
  const _PackSizeDialog({this.size, this.unit, required this.title});

  final num? size;
  final String? unit;
  final String title;

  @override
  State<_PackSizeDialog> createState() => _PackSizeDialogState();
}

class _PackSizeDialogState extends State<_PackSizeDialog> {
  late final _size = TextEditingController(
    text: widget.size == null ? '' : formatQuantity(widget.size, null),
  );
  late String _unit = widget.unit ?? Units.gram;

  @override
  void dispose() {
    _size.dispose();
    super.dispose();
  }

  void _save() {
    // „500 g“ eingetippt: Einheit aus dem Text übernehmen.
    final amount = parseAmount(_size.text);
    Navigator.pop<PackSize>(
      context,
      amount != null
          ? (size: amount.size, unit: amount.unit)
          : (size: parseNumber(_size.text), unit: _unit),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Row(
      children: [
        Expanded(
          child: TextField(
            controller: _size,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Inhalt',
              hintText: 'z. B. 500',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _save(),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: UnitField(
            value: _unit,
            units: Units.packUnits,
            allowNone: false,
            onChanged: (u) => setState(() => _unit = u ?? Units.gram),
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () =>
            Navigator.pop<PackSize>(context, (size: null, unit: _unit)),
        child: const Text('Keine'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Abbrechen'),
      ),
      FilledButton(onPressed: _save, child: const Text('OK')),
    ],
  );
}
