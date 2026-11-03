import 'package:flutter/material.dart';

import 'package:konsum_core/konsum_core.dart';

import '../state/group_session.dart';
import 'format.dart';
import 'unit_field.dart';

/// Trägt einen Preis direkt in die Historie eines Artikels ein.
Future<void> showPriceDialog(
  BuildContext context,
  GroupSession session,
  String articleId, {
  String? shopId,
}) => showDialog<void>(
  context: context,
  builder: (_) =>
      _PriceDialog(session: session, articleId: articleId, shopId: shopId),
);

class _PriceDialog extends StatefulWidget {
  const _PriceDialog({
    required this.session,
    required this.articleId,
    this.shopId,
  });

  final GroupSession session;
  final String articleId;
  final String? shopId;

  @override
  State<_PriceDialog> createState() => _PriceDialogState();
}

class _PriceDialogState extends State<_PriceDialog> {
  late final _article = widget.session.group.article(widget.articleId);
  final _price = TextEditingController();
  final _quantity = TextEditingController();
  late final _packSize = TextEditingController(
    text: _article?.packSize == null
        ? ''
        : formatQuantity(_article!.packSize, null),
  );
  late String? _unit = _article?.defaultUnit;
  late String _packUnit = _article?.packUnit ?? Units.gram;
  late String? _shopId = widget.shopId;

  @override
  void dispose() {
    _price.dispose();
    _quantity.dispose();
    _packSize.dispose();
    super.dispose();
  }

  num? get _packSizeValue =>
      Units.isCount(_unit) ? parseNumber(_packSize.text) : null;

  /// Grundpreis zu den aktuellen Eingaben, z. B. „2,58 €/kg“.
  String? get _basePrice {
    final cents = parseCents(_price.text);
    if (cents == null) return null;
    final base = baseAmount(
      quantity: parseNumber(_quantity.text),
      unit: _unit,
      packSize: _packSizeValue,
      packUnit: _packUnit,
    );
    final perBase = pricePerBase(cents, base);
    return perBase == null ? null : formatBasePrice(perBase, base!.unit);
  }

  void _save() {
    final cents = parseCents(_price.text);
    if (cents == null) return;
    widget.session.apply(
      widget.session.group
          .recordPrice(
            widget.articleId,
            cents,
            quantity: parseNumber(_quantity.text),
            unit: _unit,
            packSize: _packSizeValue,
            packUnit: _packSizeValue == null ? null : _packUnit,
            shopId: _shopId,
          )
          .changes,
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final shops = widget.session.group.shops;
    return AlertDialog(
      title: const Text('Preis eintragen'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _price,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Preis (€)',
                helperText: _basePrice,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _quantity,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'für Menge',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: UnitField(
                    value: _unit,
                    onChanged: (u) => setState(() => _unit = u),
                  ),
                ),
              ],
            ),
            if (Units.isCount(_unit)) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _packSize,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText:
                            'Inhalt je ${unitLabel(_unit ?? Units.pack)}',
                        hintText: 'optional',
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: UnitField(
                      value: _packUnit,
                      units: Units.packUnits,
                      allowNone: false,
                      onChanged: (u) =>
                          setState(() => _packUnit = u ?? Units.gram),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _shopId,
              decoration: const InputDecoration(
                labelText: 'Laden',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(child: Text('–')),
                for (final s in shops)
                  DropdownMenuItem(value: s.id, child: Text(s.name)),
              ],
              onChanged: (v) => setState(() => _shopId = v),
            ),
          ],
        ),
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
