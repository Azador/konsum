import 'package:flutter/material.dart';
import 'package:konsum_core/konsum_core.dart';

import 'format.dart';
import 'unit_field.dart';

/// Fragt die gekaufte Menge ab, z. B. um einen Kauf zu korrigieren. Null
/// bei Abbruch. Die Packungsgröße bleibt, solange die Einheit eine
/// Zähleinheit ist.
Future<Amount?> showPurchaseAmountDialog(
  BuildContext context,
  Amount? initial,
) => showDialog<Amount>(
  context: context,
  builder: (_) => _PurchaseAmountDialog(initial: initial),
);

class _PurchaseAmountDialog extends StatefulWidget {
  const _PurchaseAmountDialog({required this.initial});

  final Amount? initial;

  @override
  State<_PurchaseAmountDialog> createState() => _PurchaseAmountDialogState();
}

class _PurchaseAmountDialogState extends State<_PurchaseAmountDialog> {
  late final _quantity = TextEditingController(
    text: formatQuantity(
      widget.initial?.quantity ??
          (Units.isCount(widget.initial?.unit) ? 1 : null),
      null,
    ),
  );
  late String _unit = widget.initial?.unit ?? Units.pack;

  @override
  void dispose() {
    _quantity.dispose();
    super.dispose();
  }

  num get _step => switch (_unit) {
    Units.gram || Units.millilitre => 100,
    _ => 1,
  };

  void _stepBy(int direction) {
    final current = parseNumber(_quantity.text) ?? 0;
    final next = ((current + direction * _step) * 1000).round() / 1000;
    if (next <= 0) return;
    setState(() => _quantity.text = formatQuantity(next, null));
  }

  void _save() {
    final quantity = parseNumber(_quantity.text);
    if (quantity == null || quantity <= 0) return;
    final count = Units.isCount(_unit);
    Navigator.pop(
      context,
      Amount(
        quantity: quantity,
        unit: _unit,
        packSize: count ? widget.initial?.packSize : null,
        packUnit: count ? widget.initial?.packUnit : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pack = widget.initial;
    return AlertDialog(
      title: const Text('Gekaufte Menge'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _quantity,
            autofocus: true,
            textAlign: TextAlign.center,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Menge',
              border: const OutlineInputBorder(),
              prefixIcon: IconButton(
                tooltip: 'Weniger',
                icon: const Icon(Icons.remove),
                onPressed: () => _stepBy(-1),
              ),
              suffixIcon: IconButton(
                tooltip: 'Mehr',
                icon: const Icon(Icons.add),
                onPressed: () => _stepBy(1),
              ),
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 12),
          UnitField(
            value: _unit,
            allowNone: false,
            onChanged: (u) => setState(() => _unit = u ?? Units.pack),
          ),
          if (Units.isCount(_unit) &&
              pack?.packSize != null &&
              Units.isPackUnitFor(pack!.packUnit, _unit))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'à ${formatQuantity(pack.packSize, pack.packUnit)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 8),
          Text(
            'Die Automatik für wiederkehrende Artikel rechnet mit dieser '
            'Menge.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(onPressed: _save, child: const Text('Speichern')),
      ],
    );
  }
}
