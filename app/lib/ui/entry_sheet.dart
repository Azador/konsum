import 'package:flutter/material.dart';
import 'package:konsum_core/konsum_core.dart';

import '../state/group_session.dart';
import 'article_page.dart';
import 'format.dart';
import 'unit_field.dart';

/// Bearbeiten eines Listeneintrags: Menge, Einheit, Preis, Notizen.
Future<void> showEntrySheet(
  BuildContext context,
  GroupSession session,
  ListEntry entry,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _EntrySheet(session: session, entry: entry),
);

class _EntrySheet extends StatefulWidget {
  const _EntrySheet({required this.session, required this.entry});

  final GroupSession session;
  final ListEntry entry;

  @override
  State<_EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends State<_EntrySheet> {
  late final _quantity = TextEditingController(
    text: widget.entry.quantity == null
        ? ''
        : formatQuantity(widget.entry.quantity, null),
  );
  late final _packSize = TextEditingController(
    text: widget.entry.packSize == null
        ? ''
        : formatQuantity(widget.entry.packSize, null),
  );
  late final _price = TextEditingController(
    text: switch (widget.entry.totalCents) {
      final c? => formatCentsInput(c),
      null => '',
    },
  );

  /// Preis je Grundeinheit in Cent, ungerundet, damit Preis und Grundpreis
  /// beim Hin- und Herrechnen zusammenpassen.
  late num? _basePrice = widget.entry.basePriceCents;
  late final _basePriceText = TextEditingController(
    text: _basePrice == null ? '' : formatCentsInput(_basePrice!),
  );
  late final _note = TextEditingController(text: widget.entry.note ?? '');
  late final _privateNote = TextEditingController(
    text: widget.session.private.note(widget.entry.id) ?? '',
  );

  /// Ohne Einheit gilt Packung.
  late String _unit = widget.entry.unit ?? Units.pack;
  late String _packUnit = widget.entry.packUnit ?? Units.gram;

  @override
  void dispose() {
    for (final c in [
      _quantity,
      _packSize,
      _price,
      _basePriceText,
      _note,
      _privateNote,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  num? get _packSizeValue =>
      Units.isCount(_unit) ? parseNumber(_packSize.text) : null;

  /// Menge in der Grundeinheit nach den aktuellen Eingaben.
  BaseAmount? get _base => baseAmount(
    quantity: parseNumber(_quantity.text),
    unit: _unit,
    packSize: _packSizeValue,
    packUnit: _packUnit,
  );

  /// Grundeinheit, auch wenn die Menge (noch) fehlt.
  String get _baseUnit => baseAmount(
    quantity: 1,
    unit: _unit,
    packSize: _packSizeValue,
    packUnit: _packUnit,
  )!.unit;

  /// Menge, Einheit oder Packungsgröße geändert: Preis über den Grundpreis
  /// neu berechnen; ist nur der Preis bekannt, den Grundpreis aus ihm.
  ///
  /// Mit [keepPrice] (Inhalt je Packung geändert) bleibt der Preis und der
  /// Grundpreis folgt: Eine Packung kostet gleich viel, egal was man als
  /// Inhalt einträgt. Sonst würde beim Tippen von „500“ g der Kilopreis
  /// schon bei „5“ g festgelegt und der Preis auf das Hundertfache wachsen.
  void _amountChanged({bool keepPrice = false}) {
    final base = _base;
    if (_baseUnit != _shownBaseUnit) {
      // Andere Grundeinheit (z. B. €/kg → €/Dose): der alte Grundpreis passt
      // nicht mehr. Der Preis bleibt, der Grundpreis wird neu berechnet.
      _shownBaseUnit = _baseUnit;
      _setBasePrice(null);
    }
    if (keepPrice && parseCents(_price.text) != null) _setBasePrice(null);
    if (base != null && base.amount > 0) {
      if (_basePrice != null) {
        _price.text = formatCentsInput((_basePrice! * base.amount).round());
      } else if (parseCents(_price.text) case final cents?) {
        _setBasePrice(cents / base.amount);
      }
    }
    setState(() {});
  }

  /// Grundeinheit, zu der [_basePrice] gehört.
  late String _shownBaseUnit;

  @override
  void initState() {
    super.initState();
    _shownBaseUnit = _baseUnit;
  }

  void _priceChanged(String text) {
    final cents = parseCents(text);
    final base = _base;
    if (cents == null) {
      _setBasePrice(null);
    } else if (base != null && base.amount > 0) {
      _setBasePrice(cents / base.amount);
    }
  }

  void _basePriceChanged(String text) {
    _basePrice = parseCents(text);
    final base = _base;
    if (_basePrice != null && base != null) {
      _price.text = formatCentsInput((_basePrice! * base.amount).round());
    }
  }

  void _setBasePrice(num? cents) {
    _basePrice = cents;
    _basePriceText.text = cents == null ? '' : formatCentsInput(cents);
  }

  /// Öffnet die Artikelseite über dem Blatt; zurück geht es wieder hierher,
  /// mit den noch nicht gespeicherten Eingaben.
  Future<void> _openArticle() async {
    final group = widget.session.group;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ArticlePage(
          session: widget.session,
          articleId: widget.entry.articleId,
        ),
      ),
    );
    if (!mounted) return;
    final fresh = group
        .entries(widget.entry.listId)
        .where((e) => e.articleId == widget.entry.articleId)
        .firstOrNull;
    if (fresh == null) {
      // Artikel gelöscht: der Eintrag ist mit ihm verschwunden.
      Navigator.pop(context);
      return;
    }
    setState(() {});
  }

  void _save() {
    final e = widget.entry;
    final group = widget.session.group;
    final note = _note.text.trim();
    final packSize = _packSizeValue;
    final fields = <String, Object?>{
      'quantity': parseNumber(_quantity.text),
      // Packung ist der Standard; nicht extra speichern.
      'unit': _unit == Units.pack && e.unit == null ? null : _unit,
      'packSize': packSize,
      'packUnit': packSize == null ? null : _packUnit,
      'note': note.isEmpty ? null : note,
      'price': parseCents(_price.text),
      'basePrice': _basePrice,
    };
    final old = <String, Object?>{
      'quantity': e.quantity,
      'unit': e.unit,
      'packSize': e.packSize,
      'packUnit': e.packUnit,
      'note': e.note,
      'price': e.price,
      'basePrice': e.basePrice,
    };
    fields.removeWhere((k, v) => v == old[k]);
    if (fields.isNotEmpty) {
      widget.session.apply(group.updateEntry(e.listId, e.articleId, fields));
    }
    // Packungsgröße am Artikel merken, fürs nächste Mal – nur wenn sie hier
    // geändert wurde. Sonst schriebe Speichern einen auf der Artikelseite
    // inzwischen geänderten Inhalt mit dem alten Wert des Eintrags zurück.
    final article = group.article(e.articleId);
    if (packSize != null &&
        (packSize != e.packSize || _packUnit != e.packUnit) &&
        article != null &&
        (article.packSize != packSize || article.packUnit != _packUnit)) {
      widget.session.apply(
        group.updateArticle(article.id, {
          'packSize': packSize,
          'packUnit': _packUnit,
        }),
      );
    }
    final privateNote = _privateNote.text.trim();
    if (privateNote != (widget.session.private.note(e.id) ?? '')) {
      widget.session.applyPrivate(
        widget.session.private.setNote(e.id, privateNote),
      );
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.session.group;
    // Kann fehlen, wenn der Artikel auf der Artikelseite gelöscht wurde und
    // das Blatt darunter noch einmal gebaut wird, bevor es sich schließt.
    final article = group.article(widget.entry.articleId);
    if (article == null) return const SizedBox.shrink();
    final last = group.lastPrice(article.id);
    // Unten frei halten: Tastatur, sonst die Navigationsleiste, unter die
    // Android 15 (edge-to-edge) die App zeichnet.
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final navigation = MediaQuery.viewPaddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + (bottom > navigation ? bottom : navigation),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    article.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: const Text('Artikel'),
                  onPressed: _openArticle,
                ),
              ],
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
                      labelText: 'Menge',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => _amountChanged(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: UnitField(
                    value: _unit,
                    allowNone: false,
                    onChanged: (u) {
                      _unit = u ?? Units.pack;
                      _amountChanged();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
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
                        labelText: 'Inhalt je ${unitLabel(_unit)}',
                        hintText: 'optional',
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) => _amountChanged(keepPrice: true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: UnitField(
                      value: _packUnit,
                      units: Units.packUnits,
                      allowNone: false,
                      onChanged: (u) {
                        _packUnit = u ?? Units.gram;
                        _amountChanged(keepPrice: true);
                      },
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _basePriceText,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: '€/${unitLabel(_baseUnit)}',
                      helperText: 'Grundpreis',
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: _basePriceChanged,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _price,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Preis (€)',
                      helperText: 'für diese Menge',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: _priceChanged,
                  ),
                ),
              ],
            ),
            if (last != null)
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 4),
                child: Text(
                  [
                    'Zuletzt: ${formatCents(last.cents)}',
                    if (last.quantity != null)
                      'für ${formatAmount(quantity: last.quantity, unit: last.unit, packSize: last.packSize, packUnit: last.packUnit)}',
                    if (last.basePriceCents case final b?)
                      '(${formatBasePrice(b, last.base!.unit)})',
                    'am ${formatDate(last.millis)}',
                    if (last.shopId != null)
                      'bei ${group.shop(last.shopId!)?.name ?? '?'}',
                  ].join(' '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              decoration: const InputDecoration(
                labelText: 'Notiz für alle',
                prefixIcon: Icon(Icons.group_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _privateNote,
              decoration: const InputDecoration(
                labelText: 'Private Notiz (nur für mich)',
                prefixIcon: Icon(Icons.lock_outline),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.remove_shopping_cart_outlined),
                  label: const Text('Von Liste nehmen'),
                  onPressed: () {
                    widget.session.apply(
                      group.removeFromList(
                        widget.entry.listId,
                        widget.entry.articleId,
                      ),
                    );
                    Navigator.pop(context);
                  },
                ),
                const Spacer(),
                FilledButton(onPressed: _save, child: const Text('Speichern')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
