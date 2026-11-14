import 'package:flutter/material.dart';
import 'package:konsum_core/konsum_core.dart';

import '../state/group_session.dart';
import 'article_page.dart';
import 'auto_span.dart';
import 'format.dart';
import 'scope.dart';
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

  /// Preis je Grundeinheit in Cent, ungerundet, damit Preis und Grundpreis
  /// beim Hin- und Herrechnen zusammenpassen. Daraus folgen der Preis je
  /// Einheit und der Gesamtpreis.
  late num? _basePrice = widget.entry.basePriceCents;

  /// Preis je Einheit, wie er am Regal steht (€/Dose, €/kg, €/Packung).
  late final _shelf = TextEditingController(
    text: _basePrice == null
        ? ''
        : formatCentsInput((_basePrice! * _shelfFactor).round()),
  );
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
      _shelf,
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

  /// Was die Automatik vorschlägt (beim Öffnen berechnet).
  Amount? get _auto => widget.entry.autoAmount;

  /// Geltende Menge in der Grundeinheit nach den aktuellen Eingaben: die
  /// eigene, ohne sie die der Automatik (siehe [ListEntry.effectiveAmount]).
  BaseAmount? get _base {
    final entry = ListEntry(
      listId: widget.entry.listId,
      articleId: widget.entry.articleId,
      quantity: parseNumber(_quantity.text),
      unit: _unit,
      packSize: _packSizeValue,
      packUnit: _packUnit,
      autoAmount: _auto,
    );
    final effective = entry.effectiveBase;
    // Andere Einheit als die der Automatik: nur die eigene Menge zählt.
    return effective?.unit == _baseUnit ? effective : entry.base;
  }

  /// Schritt der Plus-/Minus-Tasten: eine Packung, Kiste, Flasche, ein
  /// Stück; bei Gewicht und Volumen 1 kg/l bzw. 100 g/ml.
  num get _step => switch (_unit) {
    Units.gram || Units.millilitre => 100,
    _ => 1,
  };

  /// Menge, von der Plus und Minus ausgehen: die eingetragene, sonst die
  /// der Automatik (in derselben Einheit), sonst bei Zähleinheiten 1.
  num get _current =>
      parseNumber(_quantity.text) ??
      (_auto?.unit == _unit ? _auto!.quantity : null) ??
      (Units.isCount(_unit) ? 1 : 0);

  void _stepBy(int direction) {
    final next = ((_current + direction * _step) * 1000).round() / 1000;
    if (next <= 0) return;
    _quantity.text = formatQuantity(next, null);
    _amountChanged();
  }

  /// Grundeinheit, auch wenn die Menge (noch) fehlt.
  String get _baseUnit => baseAmount(
    quantity: 1,
    unit: _unit,
    packSize: _packSizeValue,
    packUnit: _packUnit,
  )!.unit;

  /// Ob Preis je Einheit und Grundpreis verschieden sind und daher zwei
  /// Felder brauchen: nur bei Zähleinheiten mit Inhalt (€/Dose und €/kg).
  /// Sonst steht am Regal der Grundpreis selbst (€/kg, €/Packung).
  bool get _twoFields => Units.isCount(_unit) && _baseUnit != _unit;

  /// Grundeinheiten je Einheit: Preis je Einheit = Grundpreis × Faktor.
  num get _shelfFactor => _twoFields
      ? baseAmount(
          quantity: 1,
          unit: _unit,
          packSize: _packSizeValue,
          packUnit: _packUnit,
        )!.amount
      : 1;

  /// Gesamtpreis in Cent für die geltende Menge, falls bekannt.
  int? get _total {
    final base = _base;
    if (_basePrice == null || base == null) return null;
    return (_basePrice! * base.amount).round();
  }

  /// Letzter Preis des Artikels, im gewählten Laden bevorzugt – wie in der
  /// Liste.
  PricePoint? get _last => widget.session.group.lastPrice(
    widget.entry.articleId,
    shopId: AppScope.of(context).shopFor(widget.session),
  );

  /// Letzter Grundpreis als Vorgabe, solange keiner eingetragen ist und er
  /// zur aktuellen Grundeinheit passt. Er erscheint grau in den Feldern und
  /// wird nicht gespeichert: Nur ein selbst eingetragener Preis gilt als
  /// Preis dieses Einkaufs.
  num? get _lastBasePrice {
    if (_basePrice != null) return null;
    final last = _last;
    if (last?.base?.unit != _baseUnit) return null;
    return last!.basePriceCents;
  }

  /// Menge, für die [_total] gilt, wie [_base] sie annimmt; null, wenn bei
  /// Gewicht oder Volumen keine Menge bekannt ist.
  num? get _shownQuantity =>
      parseNumber(_quantity.text) ??
      (_auto?.unit == _unit ? _auto!.quantity : null) ??
      (Units.isCount(_unit) ? 1 : null);

  /// Menge, Einheit oder Packungsgröße geändert. Ändert sich dabei, worauf
  /// sich der Preis je Einheit bezieht (anderer Inhalt, andere
  /// Grundeinheit), bleibt der Preis je Einheit – er steht so am Regal – und
  /// der Grundpreis folgt. Beim Tippen von „500“ g gilt so jeder
  /// Zwischenstand mit demselben Packungspreis. Sonst ändert sich nur der
  /// Gesamtpreis.
  void _amountChanged() {
    final factor = _shelfFactor;
    if (factor != _shownFactor || _baseUnit != _shownBaseUnit) {
      _shownFactor = factor;
      _shownBaseUnit = _baseUnit;
      final shelf = parseCents(_shelf.text);
      _setBasePrice(shelf == null || factor <= 0 ? null : shelf / factor);
    }
    setState(() {});
  }

  /// Bezug, zu dem der angezeigte Preis je Einheit gehört.
  late num _shownFactor;
  late String _shownBaseUnit;

  @override
  void initState() {
    super.initState();
    _shownFactor = _shelfFactor;
    _shownBaseUnit = _baseUnit;
  }

  void _shelfChanged(String text) {
    final cents = parseCents(text);
    final factor = _shelfFactor;
    _setBasePrice(cents == null || factor <= 0 ? null : cents / factor);
    setState(() {});
  }

  void _basePriceChanged(String text) {
    _basePrice = parseCents(text);
    _shelf.text = _basePrice == null
        ? ''
        : formatCentsInput((_basePrice! * _shelfFactor).round());
    setState(() {});
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
      // Ohne Grundpreis und ohne Menge, aus der er sich ergäbe, bleibt ein
      // alter Gesamtpreis stehen; ist der Preis geleert, fällt er weg.
      'price': _basePrice == null
          ? (e.basePriceCents == null ? e.price : null)
          : _total,
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
    final last = _last;
    final lastBase = _lastBasePrice;
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _quantity,
                    textAlign: TextAlign.center,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Menge',
                      // Leer: Es gilt die Menge der Automatik.
                      hintText: _auto?.unit == _unit
                          ? formatQuantity(_auto!.quantity, null)
                          : null,
                      helper: switch (_auto) {
                        final a? => Text.rich(
                          autoSpan(context, 'automatisch ${formatAmountOf(a)}'),
                        ),
                        null => null,
                      },
                      border: const OutlineInputBorder(),
                      prefixIcon: IconButton(
                        tooltip: 'Weniger',
                        icon: const Icon(Icons.remove),
                        onPressed: _current - _step > 0
                            ? () => _stepBy(-1)
                            : null,
                      ),
                      suffixIcon: IconButton(
                        tooltip: 'Mehr',
                        icon: const Icon(Icons.add),
                        onPressed: () => _stepBy(1),
                      ),
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
                      onChanged: (_) => _amountChanged(),
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
                        _amountChanged();
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
                    controller: _shelf,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText:
                          '€/${unitLabel(_twoFields ? _unit : _baseUnit)}',
                      hintText: switch (lastBase) {
                        final b? => formatCentsInput(
                          (b * _shelfFactor).round(),
                        ),
                        null => null,
                      },
                      // Immer da, damit nichts springt, wenn der Preis
                      // erscheint.
                      helperText: [
                        switch (_shownQuantity) {
                          final q? => formatQuantity(q, _unit),
                          null => 'Gesamt',
                        },
                        switch ((_total, lastBase, _base)) {
                          (final t?, _, _) => formatCents(t),
                          (null, final b?, final base?) =>
                            '≈ ${formatCents((b * base.amount).round())}',
                          _ => '–',
                        },
                      ].join(': '),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: _shelfChanged,
                  ),
                ),
                if (_twoFields) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _basePriceText,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: '€/${unitLabel(_baseUnit)}',
                        hintText: switch (lastBase) {
                          final b? => formatCentsInput(b),
                          null => null,
                        },
                        helperText: 'Grundpreis',
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: _basePriceChanged,
                    ),
                  ),
                ],
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
